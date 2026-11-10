defmodule App.Model.Form do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Form
  alias App.Model.FormPage
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Repo

  # An organization's form (#950), such as EMCR's Task report: an App.Document's text
  # and the page PDF it prints on. Testing or on, it shows for every team in the
  # organization: testing prints draft PDFs only, and on publishes them (#970). SAR Duty
  # admins upload and replace it (App.Operation.SaveForm); its organization admins set
  # it off, testing, or on (App.Operation.SetFormState). docs/documents.md.
  schema "forms" do
    belongs_to :organization, Organization
    # From the text's `form '…'` and `about '…'`, so a list needn't parse it.
    field :name, :string
    field :about, :string
    field :text, :string
    # The page PDF's SHA-256, in hex, so a person can tell which page a form prints on.
    # Nil when the form has no page.
    field :page_sha256, :string
    field :state, Ecto.Enum, values: [:off, :testing, :on], default: :off
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

  @doc """
  The forms testing or on for `team`'s organization, A to Z: none for a team in no
  organization.
  """
  def shown_for(%Team{organization_id: nil}), do: []

  def shown_for(%Team{organization_id: id}) do
    Form
    |> where([f], f.organization_id == ^id and f.state != :off)
    |> order_by([f], asc: f.name)
    |> Repo.all()
  end

  @doc """
  The form `id` testing or on for `team`, or nil, so an organization's form that's off,
  or another organization's, is never found.
  """
  def get_shown(%Team{organization_id: nil}, _id), do: nil

  def get_shown(%Team{organization_id: organization_id}, id) do
    with {id, ""} <- id |> to_string() |> Integer.parse(),
         %Form{state: state} = form when state != :off <-
           Repo.get_by(Form, id: id, organization_id: organization_id) do
      form
    else
      _other -> nil
    end
  end

  @doc "How the state reads: Off, Testing, or On."
  def state_label(:off), do: "Off"
  def state_label(:testing), do: "Testing"
  def state_label(:on), do: "On"

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
