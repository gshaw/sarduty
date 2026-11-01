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
  # Every source applies as it proposes. :agent is only on old rows: an AI agent's sets
  # waited for a team admin until the MCP became read-only (#627).
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
    # :remove takes members off an activity from its Remove members page (#704).
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
        :whiteboard,
        :remove
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
end
