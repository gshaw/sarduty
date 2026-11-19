defmodule App.Model.ReportVersion do
  use App, :model

  alias App.Accounts.User
  alias App.Model.ReportVersion
  alias App.Model.SavedReport
  alias App.Repo

  # One save of a team's own report (#834): its name, description, and query as saved,
  # who saved it, the agent whose draft it came from, and What changed. Rows are never
  # changed, but for What changed when AI writes it after the save
  # (App.Operation.WriteHistoryLine). Picked values stay out: they can hold a member's ID
  # a team admin typed. Agents never read these.
  schema "report_versions" do
    belongs_to :report, SavedReport
    belongs_to :user, User
    field :name, :string
    field :about, :string
    field :query, :string
    field :change, :string
    field :agent, :string
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "A new version of `report` as it was just saved."
  def build(%SavedReport{} = report, user_id, change, agent) do
    %ReportVersion{
      report_id: report.id,
      user_id: user_id,
      name: report.name,
      about: report.about,
      query: report.query,
      change: change,
      agent: agent
    }
  end

  @doc "The report's versions, newest first, with who saved them."
  def get_all(%SavedReport{} = report) do
    ReportVersion
    |> where([v], v.report_id == ^report.id)
    |> order_by([v], desc: v.inserted_at, desc: v.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "The report's latest version, or nil."
  def latest(%SavedReport{} = report) do
    ReportVersion
    |> where([v], v.report_id == ^report.id)
    |> order_by([v], desc: v.inserted_at, desc: v.id)
    |> limit(1)
    |> preload(:user)
    |> Repo.one()
  end

  @doc "The version saved before `version`, or nil for the first."
  def previous(%ReportVersion{} = version) do
    ReportVersion
    |> where([v], v.report_id == ^version.report_id)
    |> where(
      [v],
      v.inserted_at < ^version.inserted_at or
        (v.inserted_at == ^version.inserted_at and v.id < ^version.id)
    )
    |> order_by([v], desc: v.inserted_at, desc: v.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Sets What changed on a version saved without it."
  def put_change!(%ReportVersion{} = version, change),
    do: version |> Ecto.Changeset.change(change: change) |> Repo.update!()

  @doc "The report's version with `id`, or nil."
  def get(%SavedReport{} = report, id) do
    ReportVersion |> where([v], v.report_id == ^report.id and v.id == ^id) |> Repo.one()
  end
end
