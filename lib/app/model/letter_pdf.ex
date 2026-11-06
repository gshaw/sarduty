defmodule App.Model.LetterPDF do
  use App, :model

  alias App.Model.LetterPDF
  alias App.Model.LetterPDFFile
  alias App.Model.Member
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Repo

  # A tax credit letter's PDF as it was made (#918). Downloads and emails serve it, so
  # the member gets the same file every time, whatever the team's logos are now. The
  # bytes are in LetterPDFFile, so a list of these never loads them.
  schema "letter_pdfs" do
    belongs_to :team, Team
    belongs_to :tax_credit_letter, TaxCreditLetter
    # The email's subject and the PDF's title, with the team's legal name when made.
    field :title, :string
    field :filename, :string
    field :byte_size, :integer
    has_one :file, LetterPDFFile
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Saves `attachment`, as `App.Operation.BuildTaxCreditLetterAttachment` draws it, as
  the letter's PDF, replacing any it had. Expects the letter's member loaded.
  """
  def put!(%TaxCreditLetter{member: %Member{team_id: team_id}} = letter, attachment) do
    {:ok, pdf} =
      Repo.transaction(fn ->
        delete!(letter)

        pdf =
          Repo.insert!(%LetterPDF{
            team_id: team_id,
            tax_credit_letter_id: letter.id,
            title: attachment.title,
            filename: attachment.filename,
            byte_size: byte_size(attachment.content)
          })

        Repo.insert!(%LetterPDFFile{letter_pdf_id: pdf.id, bytes: attachment.content})
        pdf
      end)

    pdf
  end

  @doc "The letter's saved PDF as an attachment, like the one `put!/2` took, or nil."
  def attachment(%TaxCreditLetter{id: id}) do
    LetterPDF
    |> join(:inner, [p], f in assoc(p, :file))
    |> where([p], p.tax_credit_letter_id == ^id)
    |> select([p, f], %{
      content: f.bytes,
      title: p.title,
      filename: p.filename,
      content_type: "application/pdf"
    })
    |> Repo.one()
  end

  def delete!(%TaxCreditLetter{id: id}) do
    LetterPDF |> where(tax_credit_letter_id: ^id) |> Repo.delete_all()
    :ok
  end

  @doc """
  Up to `limit` letters with no saved PDF and an id past `after_id`, oldest first, with
  their member and team.
  """
  def missing(after_id, limit) do
    TaxCreditLetter
    |> join(:left, [l], p in LetterPDF, on: p.tax_credit_letter_id == l.id)
    |> where([l, p], is_nil(p.id) and l.id > ^after_id)
    |> order_by([l], asc: l.id)
    |> limit(^limit)
    |> preload(member: :team)
    |> Repo.all()
  end
end
