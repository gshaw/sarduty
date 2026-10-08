defmodule App.Model.ChangeSet do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Group
  alias App.Model.Team
  alias App.Repo

  # A list of D4H edits, with what proposed them and who applied them. Every write
  # SAR Duty makes to D4H goes through one (#174); App.Operation.ApplyChangeSet makes
  # the writes. An attendance set names its activity, a group rule's set its group.
  # An agent's set (#216) waits for a team admin to apply or discard it; the other
  # sources apply as they propose.
  schema "change_sets" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :group, Group
    belongs_to :proposed_by_user, User
    belongs_to :applied_by_user, User
    # :edit is a team admin changing one record of a hosted team (docs/hosted-d4h.md).
    field :source, Ecto.Enum, values: [:door, :group_rule, :attendance_import, :agent, :edit]
    field :summary, :string
    field :applied_at, :utc_datetime_usec
    field :discarded_at, :utc_datetime_usec
    has_many :rows, ChangeSetRow, preload_order: [asc: :id]
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Saves a change set and its rows, all proposed. `rows` are `ChangeSetRow` structs
  without the set or team.
  """
  def propose!(%ChangeSet{team_id: team_id} = change_set, rows) when is_integer(team_id) do
    rows = Enum.map(rows, &%{&1 | team_id: team_id, status: :proposed})
    Repo.insert!(%{change_set | rows: rows})
  end

  def mark_applied!(%ChangeSet{} = change_set, %User{} = user, now) do
    change_set |> change(applied_by_user_id: user.id, applied_at: now) |> Repo.update!()
  end

  def discard!(%ChangeSet{} = change_set, now),
    do: change_set |> change(discarded_at: now) |> Repo.update!()

  @doc "A team's change set by id, with its rows. Raises when it's another team's."
  def find!(%Team{} = team, id) do
    ChangeSet
    |> where(team_id: ^team.id)
    |> Repo.get!(id)
    |> Repo.preload([:activity, :proposed_by_user, :applied_by_user, rows: :member])
  end

  @doc "Whether the set waits for a team admin: an agent's, neither applied nor discarded."
  def waiting?(%ChangeSet{source: :agent, applied_at: nil, discarded_at: nil}), do: true
  def waiting?(%ChangeSet{}), do: false

  @doc "An agent's change sets that wait for a team admin, oldest first."
  def get_waiting(team_id) do
    ChangeSet
    |> waiting_query(team_id)
    |> order_by([s], asc: s.inserted_at, asc: s.id)
    |> preload([:activity, :proposed_by_user, :rows])
    |> Repo.all()
  end

  def count_waiting(team_id), do: ChangeSet |> waiting_query(team_id) |> Repo.aggregate(:count)

  @doc "An agent's change sets a team admin applied or discarded, newest first."
  def get_recent_decided(team_id, limit) do
    ChangeSet
    |> where([s], s.team_id == ^team_id and s.source == :agent)
    |> where([s], not is_nil(s.applied_at) or not is_nil(s.discarded_at))
    |> order_by([s], desc: s.updated_at, desc: s.id)
    |> limit(^limit)
    |> preload([:activity, :proposed_by_user, :applied_by_user, :rows])
    |> Repo.all()
  end

  defp waiting_query(query, team_id) do
    where(
      query,
      [s],
      s.team_id == ^team_id and s.source == :agent and is_nil(s.applied_at) and
        is_nil(s.discarded_at)
    )
  end
end
