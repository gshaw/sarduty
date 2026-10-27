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
    # :edit is a team admin changing one record of a team on SAR Duty Records
    # (docs/records.md), or a group or who is in it on any team (#546). :member is a
    # member changing their own details (#156). :equipment adds or removes items on an
    # activity (#271). :template adds a template's groups to an activity (#162), and
    # :invite the members a team admin picks on its Add members page (#564). :tags sets
    # an activity's tags from its tags page (#323).
    # :attendance_import is only on old rows: the page that made them is gone (#424).
    # :chores sends a team admin's accepted chores as a D4H event (#341). :certificates
    # adds a member's certificate to D4H, as an award with the file on it (#493).
    # :whiteboard posts, changes, archives, or deletes a whiteboard note (#515).
    field :source, Ecto.Enum,
      values: [
        :door,
        :group_rule,
        :attendance_import,
        :agent,
        :edit,
        :member,
        :equipment,
        :template,
        :invite,
        :tags,
        :chores,
        :certificates,
        :whiteboard
      ]

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

  @doc "Marks the set applied by `user`, or by nobody logged in: a reply from an email."
  def mark_applied!(%ChangeSet{} = change_set, user, now)
      when is_nil(user) or is_struct(user, User) do
    change_set |> change(applied_by_user_id: user && user.id, applied_at: now) |> Repo.update!()
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

  @doc """
  What an agent's set changes, from its rows: `:chores`, `:activity_tags`, or
  `:attendance`. Each propose tool makes one kind (#595).
  """
  def proposal_kind(%ChangeSet{rows: rows}) do
    cond do
      Enum.any?(rows, &(&1.action == :add_chore)) -> :chores
      Enum.any?(rows, &(&1.action == :set_activity_tags)) -> :activity_tags
      true -> :attendance
    end
  end

  @doc "The heading for an agent's set, named for what it changes, never the agent's words."
  def proposal_title(%ChangeSet{} = change_set) do
    case proposal_kind(change_set) do
      :chores -> "Chores to add"
      :activity_tags -> "Activity tag changes"
      :attendance -> "Attendance changes"
    end
  end

  @doc "How many things the set changes, in its kind's words: chores, activities, or changes."
  def proposal_count(%ChangeSet{rows: rows} = change_set) do
    n = length(rows)

    case proposal_kind(change_set) do
      :chores -> Service.Format.count(n, one: "%d chore", many: "%d chores")
      :activity_tags -> Service.Format.count(n, one: "%d activity", many: "%d activities")
      :attendance -> Service.Format.count(n, one: "%d change", many: "%d changes")
    end
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

  @doc "An agent's change sets, newest first."
  def get_proposed(team_id) do
    ChangeSet
    |> where([s], s.team_id == ^team_id and s.source == :agent)
    |> order_by([s], desc: s.inserted_at, desc: s.id)
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
