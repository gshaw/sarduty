defmodule App.Model.PublishedPDF do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Form
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.PublishedPDF
  alias App.Model.PublishedPDFFile
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Repo

  # A document as it was published (#918, #950, #970): the PDF, the values it kept, and
  # what its verify page shows. A draft is never saved, so every row here has an ID the
  # verify site finds it by. A subject, such as a member's year or an activity, has one
  # current PDF for each definition: publishing again keeps the old one, Replaced, and
  # withdrawing one ends it with none. Nothing is deleted but with the team. Downloads
  # and emails serve the saved bytes, whatever the team's logos or the definition are
  # now. The bytes are in PublishedPDFFile, so a list of these never loads them.
  schema "published_pdfs" do
    belongs_to :team, Team
    # The definition's name, such as "Tax credit letter".
    field :name, :string
    # What it's for: `member:45:2026` for a member's year, `activity:812` for an activity.
    field :subject, :string
    # Its ID: 15 characters, stored without dashes. A letter from before #970 has its
    # old reference number until App.Worker.RenewLetterCodesWorker gives it an ID; an
    # old reference number never verifies.
    field :code, :string, redact: true
    belongs_to :tax_credit_letter, TaxCreditLetter
    belongs_to :member, Member
    field :year, :integer
    belongs_to :activity, Activity
    # A form's, and the version it printed from: nil once the form is gone.
    belongs_to :form, Form
    field :form_version, :integer
    # Who published it. Nil for a letter.
    belongs_to :user, User
    belongs_to :replaced_by, PublishedPDF
    field :withdrawn_at, :utc_datetime_usec
    belongs_to :withdrawn_by, User
    # The email's subject and the PDF's title, with the team's legal name when made.
    field :title, :string
    field :filename, :string
    field :byte_size, :integer
    field :sha256, :string
    # The values it printed that `keep` names, by name, such as `hours.primary`.
    field :keep, :map, default: %{}, redact: true
    # Every answer it printed with, by name.
    field :answers, :map, default: %{}, redact: true
    # What its verify page shows, `[%{"label", "text"}]`, as `verify shows` printed it.
    field :shows, {:array, :map}, default: [], redact: true
    has_one :file, PublishedPDFFile
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @code_length 15

  @doc """
  A new ID: 15 random characters from the ID card alphabet, about 74 bits, stored
  without dashes. Too many to guess even without the verify site's miss limit.
  """
  def generate_code, do: MemberCard.random_code(@code_length)

  @doc "An ID as people read it: `K7Q4M-2XA9H-VB3TN`."
  def format_code(<<a::binary-5, b::binary-5, c::binary-5>>), do: "#{a}-#{b}-#{c}"
  def format_code(code), do: code

  @doc """
  What someone typed or scanned, as a stored ID, or nil when it can't be one. Case,
  spaces, and dashes don't matter. A letter's reference number from before #970 is nil:
  only 15-character IDs verify.
  """
  def parse_code(input) when is_binary(input) do
    code = input |> String.upcase() |> String.replace(~r/[\s-]/, "")
    if String.length(code) == @code_length and code =~ ~r/^[2-9A-HJKMNP-TV-Z]+$/, do: code
  end

  def parse_code(_input), do: nil

  # cspell:ignore HJKMNP -- the ID card alphabet, MemberCard's: no 0/O, 1/I/L, or U

  @doc """
  The PDF's page on the verify site, which its verify code opens:
  `https://verify.sarduty.com/K7Q4M-2XA9H-VB3TN`.
  """
  def verify_link(code), do: "#{Web.VerifyHost.url()}/#{format_code(code)}"

  @doc "`:current`, `:replaced`, or `:withdrawn`."
  def status(%PublishedPDF{withdrawn_at: %DateTime{}}), do: :withdrawn
  def status(%PublishedPDF{replaced_by_id: id}) when is_integer(id), do: :replaced
  def status(%PublishedPDF{}), do: :current

  @doc "A tax credit letter's subject: the member and the year."
  def letter_subject(member_id, year), do: "member:#{member_id}:#{year}"

  @doc """
  Saves a PDF just printed as published, in one transaction: `attrs` say what it is
  (`team_id`, `name`, `subject`, `code`, and what it's about), `printed` is
  `%{attachment, keep, shows}`. The subject's current PDF of the same name becomes
  Replaced by it. `current_id` is the current PDF's id the person saw, nil for none:
  when another took its place since, nothing is saved and it's `{:error, :stale}`.
  Gives `{:ok, pdf}`. Call it inside the caller's transaction when it writes more.
  """
  def publish(attrs, printed, current_id) do
    Repo.transaction(fn ->
      current = get_current(attrs.team_id, attrs.name, attrs.subject)

      if (current && current.id) != current_id,
        do: Repo.rollback(:stale)

      # The current PDF stops being current before the new one is, since a subject has
      # one current PDF at a time: for a moment it's replaced by itself.
      if current, do: set_replaced_by!(current, current.id)

      pdf = insert!(attrs, printed)
      if current, do: set_replaced_by!(current, pdf.id)
      pdf
    end)
  end

  defp insert!(attrs, %{attachment: attachment} = printed) do
    pdf =
      Repo.insert!(%PublishedPDF{
        team_id: attrs.team_id,
        name: attrs.name,
        subject: attrs.subject,
        code: attrs.code,
        tax_credit_letter_id: attrs[:tax_credit_letter_id],
        member_id: attrs[:member_id],
        year: attrs[:year],
        activity_id: attrs[:activity_id],
        form_id: attrs[:form_id],
        form_version: attrs[:form_version],
        user_id: attrs[:user_id],
        answers: attrs[:answers] || %{},
        keep: printed[:keep] || %{},
        shows: printed[:shows] || [],
        title: attachment.title,
        filename: attachment.filename,
        byte_size: byte_size(attachment.content),
        sha256: :sha256 |> :crypto.hash(attachment.content) |> Base.encode16(case: :lower)
      })

    Repo.insert!(%PublishedPDFFile{published_pdf_id: pdf.id, bytes: attachment.content})
    pdf
  end

  defp set_replaced_by!(pdf, id),
    do: PublishedPDF |> where(id: ^pdf.id) |> Repo.update_all(set: [replaced_by_id: id])

  @doc """
  Replaces a PDF's ID, file, and what it printed with `printed`, a new print of the same
  document, in one transaction (App.Operation.RenewLetterCodes). Its row and date stay.
  """
  def reprint!(%PublishedPDF{} = pdf, %{attachment: attachment, code: code} = printed) do
    {:ok, pdf} =
      Repo.transaction(fn ->
        PublishedPDFFile
        |> where(published_pdf_id: ^pdf.id)
        |> Repo.update_all(set: [bytes: attachment.content])

        pdf
        |> Ecto.Changeset.change(
          code: code,
          title: attachment.title,
          filename: attachment.filename,
          byte_size: byte_size(attachment.content),
          sha256: :sha256 |> :crypto.hash(attachment.content) |> Base.encode16(case: :lower),
          keep: printed.keep,
          shows: printed.shows
        )
        |> Repo.update!()
      end)

    pdf
  end

  @doc """
  Marks the PDF withdrawn by `user` at `now`: `{:ok, pdf}`, or `{:error, :not_current}`
  when it was replaced or withdrawn meanwhile, so two at once withdraw it once.
  """
  def withdraw(%PublishedPDF{id: id}, %User{id: user_id}, now) do
    at = DateTime.truncate(now, :microsecond)

    {count, _rows} =
      PublishedPDF
      |> where([p], p.id == ^id and is_nil(p.withdrawn_at) and is_nil(p.replaced_by_id))
      |> Repo.update_all(set: [withdrawn_at: at, withdrawn_by_id: user_id])

    if count == 1, do: {:ok, Repo.get!(PublishedPDF, id)}, else: {:error, :not_current}
  end

  @doc "The subject's current PDF of the definition `name`, or nil."
  def get_current(team_id, name, subject) do
    PublishedPDF
    |> where([p], p.team_id == ^team_id and p.name == ^name and p.subject == ^subject)
    |> where([p], is_nil(p.replaced_by_id) and is_nil(p.withdrawn_at))
    |> Repo.one()
  end

  @doc """
  The subject's PDFs of the definition `name`, newest first, with who published and
  withdrew each: the current one, if any, then those it replaced or that were withdrawn.
  """
  def get_all_for(team_id, name, subject) do
    PublishedPDF
    |> where([p], p.team_id == ^team_id and p.name == ^name and p.subject == ^subject)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> preload([:user, :withdrawn_by])
    |> Repo.all()
  end

  @doc "The activity's PDFs, newest first, with who published and withdrew each: its History."
  def get_all_for_activity(team_id, activity_id) do
    PublishedPDF
    |> where([p], p.team_id == ^team_id and p.activity_id == ^activity_id)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> preload([:user, :withdrawn_by])
    |> Repo.all()
  end

  @doc "The team's PDF `id`, or nil."
  def get(%Team{id: team_id}, id) do
    case id |> to_string() |> Integer.parse() do
      {id, ""} -> Repo.get_by(PublishedPDF, id: id, team_id: team_id)
      _other -> nil
    end
  end

  @doc "The letter's current PDF, or nil."
  def current_for_letter(%TaxCreditLetter{id: id}) do
    PublishedPDF
    |> where([p], p.tax_credit_letter_id == ^id)
    |> where([p], is_nil(p.replaced_by_id) and is_nil(p.withdrawn_at))
    |> Repo.one()
  end

  @doc "The letter's current PDF as an attachment, like the one `publish/3` took, or nil."
  def letter_attachment(%TaxCreditLetter{} = letter) do
    case current_for_letter(letter) do
      nil -> nil
      pdf -> attachment(pdf)
    end
  end

  @doc "A published PDF as an attachment, with its bytes."
  def attachment(%PublishedPDF{id: id}) do
    PublishedPDF
    |> where([p], p.id == ^id)
    |> join(:inner, [p], f in assoc(p, :file))
    |> select([p, f], %{
      content: f.bytes,
      title: p.title,
      filename: p.filename,
      content_type: "application/pdf"
    })
    |> Repo.one!()
  end

  @doc """
  The PDF with this stored ID, for the verify site, with its team, the team's
  organization, and the PDF that replaced it; or nil.
  """
  def find_for_verify(code) do
    PublishedPDF
    |> where([p], p.code == ^code)
    |> verify_preload()
    |> Repo.one()
  end

  defp verify_preload(query), do: preload(query, [:replaced_by, team: :organization])
end
