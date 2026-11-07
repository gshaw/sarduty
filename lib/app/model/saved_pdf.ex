defmodule App.Model.SavedPDF do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Form
  alias App.Model.Member
  alias App.Model.SavedPDF
  alias App.Model.SavedPDFFile
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Repo

  # A document's PDF as it was made (#918, #950): a tax credit letter's, or a form's for
  # an activity. Downloads and emails serve it, so a person gets the same file every
  # time, whatever the team's logos or the form are now. The bytes are in SavedPDFFile,
  # so a list of these never loads them.
  schema "saved_pdfs" do
    belongs_to :team, Team
    # A letter has one, replaced when the letter is.
    belongs_to :tax_credit_letter, TaxCreditLetter
    # A form's PDFs: one for each download, none replaced. The form, nil once it's
    # gone, and the version it printed from.
    belongs_to :activity, Activity
    belongs_to :form, Form
    field :form_version, :integer
    # Who made it. Nil for a letter.
    belongs_to :user, User
    # The email's subject and the PDF's title, with the team's legal name when made.
    field :title, :string
    field :filename, :string
    field :byte_size, :integer
    # The values it printed that `keep` names, by name, such as `hours.primary`.
    field :keep, :map, default: %{}, redact: true
    has_one :file, SavedPDFFile
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Saves `attachment`, as `App.Operation.PrintTaxCreditLetter` prints it, as the
  letter's PDF, replacing any it had. Expects the letter's member loaded.
  """
  def put_letter!(%TaxCreditLetter{member: %Member{team_id: team_id}} = letter, attachment) do
    {:ok, pdf} =
      Repo.transaction(fn ->
        delete_letter!(letter)
        insert!(%SavedPDF{team_id: team_id, tax_credit_letter_id: letter.id}, attachment)
      end)

    pdf
  end

  @doc """
  Saves `attachment` as a new PDF of `form` at its version for the activity, made by
  `user`, with the values it `keep`s. A form saves one each time it prints, and none
  replaces another.
  """
  def add_for_form!(
        %Form{} = form,
        %Activity{} = activity,
        %User{} = user,
        attachment,
        keep \\ %{}
      ) do
    {:ok, pdf} =
      Repo.transaction(fn ->
        insert!(
          %SavedPDF{
            team_id: activity.team_id,
            activity_id: activity.id,
            form_id: form.id,
            form_version: form.version,
            user_id: user.id,
            keep: keep
          },
          attachment
        )
      end)

    pdf
  end

  @doc """
  How many PDFs each form made since `since`, every team's together: `%{form_id =>
  count}`, a count only, for the organization's Forms list.
  """
  def form_counts(form_ids, %DateTime{} = since) do
    SavedPDF
    |> where([p], p.form_id in ^form_ids and p.inserted_at >= ^since)
    |> group_by([p], p.form_id)
    |> select([p], {p.form_id, count(p.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp insert!(%SavedPDF{} = pdf, attachment) do
    pdf =
      Repo.insert!(%{
        pdf
        | title: attachment.title,
          filename: attachment.filename,
          byte_size: byte_size(attachment.content)
      })

    Repo.insert!(%SavedPDFFile{saved_pdf_id: pdf.id, bytes: attachment.content})
    pdf
  end

  @doc "The letter's saved PDF as an attachment, like the one `put_letter!/2` took, or nil."
  def letter_attachment(%TaxCreditLetter{id: id}),
    do: SavedPDF |> where([p], p.tax_credit_letter_id == ^id) |> attachment_query() |> Repo.one()

  @doc "A saved PDF as an attachment, with its bytes."
  def attachment(%SavedPDF{id: id}),
    do: SavedPDF |> where([p], p.id == ^id) |> attachment_query() |> Repo.one!()

  defp attachment_query(query) do
    query
    |> join(:inner, [p], f in assoc(p, :file))
    |> select([p, f], %{
      content: f.bytes,
      title: p.title,
      filename: p.filename,
      content_type: "application/pdf"
    })
  end

  def delete_letter!(%TaxCreditLetter{id: id}) do
    SavedPDF |> where(tax_credit_letter_id: ^id) |> Repo.delete_all()
    :ok
  end
end
