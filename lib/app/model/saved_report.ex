defmodule App.Model.SavedReport do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Repo

  # A team's own report (#768): its query, never its rows. The query is checked again on
  # every run, so a field that goes fails with a message, never wrong rows. Every save
  # keeps a version (#834, App.Model.ReportVersion). A deleted report keeps them for 30
  # days under Recently deleted, then the nightly prune deletes both.
  schema "reports" do
    belongs_to :team, Team
    belongs_to :created_by_user, User
    field :name, TrimmedString
    field :about, TrimmedString
    field :query, :string
    # Picked values can be text a team admin typed, such as a member's ID.
    field :values, :map, default: %{}, redact: true
    field :agent, :string
    field :deleted_at, :utc_datetime
    # What changed, for the version a save of a saved report keeps.
    field :change, TrimmedString, virtual: true
    timestamps(type: :utc_datetime)
  end

  @max_name 80
  @max_about 200
  @max_change 100
  @deleted_days 30

  @doc "The longest a name may be."
  def max_name, do: @max_name

  @doc "The longest What changed may be."
  def max_change, do: @max_change

  @doc "How many days a deleted report stays under Recently deleted."
  def deleted_days, do: @deleted_days

  @doc """
  A changeset for what a team admin types: name, description (`about`), query, picked
  values, and What changed.
  """
  def changeset(%SavedReport{} = report, params) do
    report
    |> cast(params, [:name, :about, :query, :values, :change])
    |> validate_required([:name], message: "Enter a name for the report")
    |> validate_required([:query], message: "Write a query, starting with select")
    |> validate_length(:name,
      max: @max_name,
      message: "Name must be #{@max_name} characters or fewer"
    )
    |> validate_length(:about,
      max: @max_about,
      message: "Description must be #{@max_about} characters or fewer"
    )
    |> validate_length(:change,
      max: @max_change,
      message: "What changed must be #{@max_change} characters or fewer"
    )
  end

  @doc "The team's reports, newest first, with who made them."
  def get_all(%Team{} = team) do
    SavedReport
    |> where([r], r.team_id == ^team.id and is_nil(r.deleted_at))
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> preload(:created_by_user)
    |> Repo.all()
  end

  @doc "The team's report with `id`, or nil, or nil when it was deleted."
  def get(%Team{} = team, id) do
    SavedReport
    |> where([r], r.team_id == ^team.id and r.id == ^id and is_nil(r.deleted_at))
    |> preload(:created_by_user)
    |> Repo.one()
  end

  @doc "The team's deleted reports still under Recently deleted, latest deleted first."
  def get_deleted(%Team{} = team) do
    SavedReport
    |> where([r], r.team_id == ^team.id and not is_nil(r.deleted_at))
    |> order_by([r], desc: r.deleted_at, desc: r.id)
    |> preload(:created_by_user)
    |> Repo.all()
  end

  @doc "The team's deleted report with `id`, or nil."
  def get_deleted(%Team{} = team, id) do
    SavedReport
    |> where([r], r.team_id == ^team.id and r.id == ^id and not is_nil(r.deleted_at))
    |> Repo.one()
  end

  @doc """
  Deletes reports deleted more than #{@deleted_days} days ago, and their versions with
  them. Returns how many.
  """
  def prune_deleted(now) do
    cutoff = DateTime.add(now, -@deleted_days, :day)
    {count, _} = SavedReport |> where([r], r.deleted_at < ^cutoff) |> Repo.delete_all()
    count
  end
end
