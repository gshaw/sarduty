defmodule App.Model.Form do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Form
  alias App.Model.FormPage
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Repo

  # A form (#950), such as EMCR's Task report: an App.Document's text and the page PDF
  # it prints on. It belongs to an organization or to one team (#1083), never both: an
  # organization's shows for every team in it, and a team's only for that team, while
  # SAR Duty has team forms on for it. Testing prints draft PDFs only, and on publishes
  # them (#970). SAR Duty admins upload and replace an organization's; a team's admins
  # start their own from its page, and save its text (App.Operation.SaveForm).
  # Its organization admins, or the team's admins, set it off, testing, or on
  # (App.Operation.SetFormState). docs/documents.md.
  schema "forms" do
    belongs_to :organization, Organization
    belongs_to :team, Team
    # From the text's `form '…'` and `about '…'`, so a list needn't parse it.
    field :name, :string
    field :about, :string
    # "" until a team's new form is written (written?/1).
    field :text, :string
    # The page PDF's SHA-256, in hex, so a person can tell which page a form prints on.
    # Nil when the form has no page.
    field :page_sha256, :string
    field :state, Ecto.Enum, values: [:off, :testing, :on], default: :off
    # Starts at 1, and goes up each time it's replaced. Writing a team's new form keeps
    # it 1.
    field :version, :integer, default: 1
    # Who last changed it, uploading it or turning it on or off, and when: updated_at.
    belongs_to :user, User
    has_one :page, FormPage
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The organization's forms, or the team's own, A to Z."
  def get_all(owner), do: owner |> owned_by() |> order_by([f], asc: f.name) |> Repo.all()

  defp owned_by(%Organization{id: id}), do: where(Form, [f], f.organization_id == ^id)
  defp owned_by(%Team{id: id}), do: where(Form, [f], f.team_id == ^id)

  @doc """
  The forms testing or on for `team`, A to Z: its organization's, and its own while
  team forms are on (#1083). An organization's form replaces the team's of the same
  name, so the team's shows only until its organization has one.
  """
  def shown_for(%Team{} = team) do
    organization = organization_forms(team)
    names = MapSet.new(organization, & &1.name)
    own = team |> own_forms() |> Enum.reject(&MapSet.member?(names, &1.name))
    Enum.sort_by(organization ++ own, & &1.name)
  end

  @doc """
  The team's organization's forms testing or on, A to Z: the ones its activities show,
  which its team admins see read-only on Team settings' Forms tab.
  """
  def organization_forms(%Team{organization_id: nil}), do: []

  def organization_forms(%Team{organization_id: id}),
    do:
      Form
      |> where([f], f.organization_id == ^id and f.state != :off)
      |> order_by([f], asc: f.name)
      |> Repo.all()

  @doc "The team's organization's form `id`, testing or on, or nil."
  def get_organization_form(%Team{} = team, id) do
    case id |> to_string() |> Integer.parse() do
      {id, ""} -> team |> organization_forms() |> Enum.find(&(&1.id == id))
      _other -> nil
    end
  end

  @doc """
  Whether the team's own `form` is replaced on its activities by one of its
  organization's of the same name (`shown_for/1`), saved after it.
  """
  def replaced?(%Form{team_id: id, name: name}, %Team{id: id} = team),
    do: team |> organization_forms() |> Enum.any?(&(&1.name == name))

  def replaced?(_form, _team), do: false

  defp own_forms(%Team{forms_enabled: false}), do: []

  defp own_forms(%Team{id: id}),
    do: Form |> where([f], f.team_id == ^id and f.state != :off) |> Repo.all()

  @doc """
  The form `id` testing or on for `team`, or nil, so a form that's off, another
  organization's or team's, or the team's own while team forms are off, is never found.
  """
  def get_shown(%Team{} = team, id) do
    case id |> to_string() |> Integer.parse() do
      {id, ""} -> team |> shown_for() |> Enum.find(&(&1.id == id))
      _other -> nil
    end
  end

  @doc "Whether `form` is testing or on for `team`: one `shown_for/1` lists."
  def shown?(%Form{id: id}, %Team{} = team), do: team |> shown_for() |> Enum.any?(&(&1.id == id))

  @doc """
  Whether the form has its text. A team's new form starts as its page alone, off, until
  its text is saved (#1083).
  """
  def written?(%Form{text: text}), do: text not in [nil, ""]

  @doc """
  Which save the form is at: its version, or 0 before its first text, which keeps
  version 1. Change form compares it at Save, so a newer save is never replaced unseen
  (#1089).
  """
  def saved_mark(%Form{} = form), do: if(written?(form), do: form.version, else: 0)

  @doc "How the state reads: Off, Testing, or On."
  def state_label(:off), do: "Off"
  def state_label(:testing), do: "Testing"
  def state_label(:on), do: "On"

  @doc "What a form that isn't shown says, and who an organization's sends you to."
  def off_text(%Form{team_id: nil}),
    do: "This form is turned off. Ask your organization to turn it on."

  def off_text(%Form{}), do: "This form is turned off."

  @doc """
  The organization's or the team's own form `id`, or nil, so another owner's is never
  found.
  """
  def get(owner, id) do
    case id |> to_string() |> Integer.parse() do
      {id, ""} -> owner |> owned_by() |> where([f], f.id == ^id) |> Repo.one()
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
