defmodule App.Model.Form do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Form
  alias App.Model.FormPage
  alias App.Model.Organization
  alias App.Repo

  # An organization's form (#950), such as EMCR's Task report: an App.Document's text
  # and the page PDF it prints on. Once on, it shows for every team in the organization.
  # SAR Duty admins upload and replace it (App.Operation.SaveForm); its organization
  # admins turn it on and off (App.Operation.SetFormEnabled). docs/documents.md.
  schema "forms" do
    belongs_to :organization, Organization
    # From the text's `form '…'` and `about '…'`, so a list needn't parse it.
    field :name, :string
    field :about, :string
    field :text, :string
    # The page PDF's SHA-256, in hex, so a person can tell which page a form prints on.
    # Nil when the form has no page.
    field :page_sha256, :string
    field :enabled, :boolean, default: false
    # Starts at 1, and goes up each time a SAR Duty admin replaces it.
    field :version, :integer, default: 1
    # Who last changed it, uploading it or turning it on or off, and when: updated_at.
    belongs_to :user, User
    has_one :page, FormPage
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The organization's forms, A to Z."
  def get_all(%Organization{id: id}),
    do: Form |> where([f], f.organization_id == ^id) |> order_by([f], asc: f.name) |> Repo.all()

  @doc "The organization's form `id`, or nil, so another organization's is never found."
  def get(%Organization{id: organization_id}, id) do
    case id |> to_string() |> Integer.parse() do
      {id, ""} -> Repo.get_by(Form, id: id, organization_id: organization_id)
      _other -> nil
    end
  end

  @doc "The form's page PDF, or nil."
  def page_bytes(%Form{id: id}),
    do: FormPage |> where([p], p.form_id == ^id) |> select([p], p.bytes) |> Repo.one()

  @doc "A page PDF's SHA-256, in lowercase hex."
  def sha256(bytes) when is_binary(bytes),
    do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

  def sha256(nil), do: nil
end
