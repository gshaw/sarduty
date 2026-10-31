defmodule App.Model.SavedReport do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Repo

  # A team's own report (#768): its query, never its rows. The query is checked again on
  # every run, so a field that goes fails with a message, never wrong rows. `slug` is its
  # URL, unique on the team and never a built-in report's.
  schema "reports" do
    belongs_to :team, Team
    belongs_to :created_by_user, User
    field :slug, :string
    field :name, TrimmedString
    field :about, TrimmedString
    field :query, :string
    # Picked values can be text a team admin typed, such as a member's ID.
    field :values, :map, default: %{}, redact: true
    field :agent, :string
    timestamps(type: :utc_datetime)
  end

  @max_name 80
  @max_about 200

  @doc "A changeset for what a team admin types: name, about, query, and picked values."
  def changeset(%SavedReport{} = report, params) do
    report
    |> cast(params, [:name, :about, :query, :values])
    |> validate_required([:name], message: "Enter a name for the report")
    |> validate_required([:query], message: "Write a query, starting with select")
    |> validate_length(:name,
      max: @max_name,
      message: "Name must be #{@max_name} characters or fewer"
    )
    |> validate_length(:about,
      max: @max_about,
      message: "About must be #{@max_about} characters or fewer"
    )
  end

  @doc "The team's reports, newest first, with who made them."
  def get_all(%Team{} = team) do
    SavedReport
    |> where([r], r.team_id == ^team.id)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> preload(:created_by_user)
    |> Repo.all()
  end

  @doc "The team's report with `slug`, or nil."
  def get_by_slug(%Team{} = team, slug) do
    SavedReport
    |> where([r], r.team_id == ^team.id and r.slug == ^slug)
    |> preload(:created_by_user)
    |> Repo.one()
  end

  @doc "The slugs the team's reports use, for a new one to steer clear of."
  def slugs(%Team{} = team),
    do: SavedReport |> where([r], r.team_id == ^team.id) |> select([r], r.slug) |> Repo.all()
end
