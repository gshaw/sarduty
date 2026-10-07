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
  schema "change_sets" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :group, Group
    belongs_to :proposed_by_user, User
    belongs_to :applied_by_user, User
    field :source, Ecto.Enum, values: [:door, :group_rule, :attendance_import]
    field :applied_at, :utc_datetime_usec
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
end
