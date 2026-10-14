defmodule App.Model.GroupParent do
  use App, :model

  alias App.Model.Group
  alias App.Model.GroupParent
  alias App.Repo

  # The group a group starts from (#327). The group's rule is every endorsement the
  # parent's rule requires, and its own. It copies the parent's rule, not its members, so
  # someone added to the parent by hand without its endorsements does not get in. Both
  # groups are by D4H id, so the link survives the sync recreating a row.
  schema "group_parents" do
    belongs_to :team, App.Model.Team
    field :d4h_group_id, :integer
    field :parent_d4h_group_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def set!(%Group{team_id: team_id} = group, %Group{team_id: team_id} = parent) do
    %GroupParent{
      team_id: team_id,
      d4h_group_id: group.d4h_group_id,
      parent_d4h_group_id: parent.d4h_group_id
    }
    |> Repo.insert!(
      on_conflict: {:replace, [:parent_d4h_group_id, :updated_at]},
      conflict_target: [:team_id, :d4h_group_id]
    )
  end

  def clear!(%Group{} = group) do
    GroupParent
    |> where([gp], gp.team_id == ^group.team_id and gp.d4h_group_id == ^group.d4h_group_id)
    |> Repo.delete_all()
  end

  @doc "Each D4H group id with its parent's, for the team. A deleted parent drops out."
  def parents_by_group(team_id) do
    GroupParent
    |> join(:inner, [gp], g in Group,
      on: g.team_id == gp.team_id and g.d4h_group_id == gp.parent_d4h_group_id
    )
    |> where([gp], gp.team_id == ^team_id)
    |> select([gp], {gp.d4h_group_id, gp.parent_d4h_group_id})
    |> Repo.all()
    |> Map.new()
  end

  @doc "A query for the D4H ids of the team's groups that start from another."
  def child_d4h_group_ids_query(team_id) do
    GroupParent
    |> where([gp], gp.team_id == ^team_id)
    |> select([gp], gp.d4h_group_id)
  end

  @doc """
  Pure. The D4H ids of the group's parent, its parent's parent, and so on, nearest first.
  A loop already in the data stops instead of running forever.
  """
  def ancestors(d4h_group_id, parents), do: climb(parents[d4h_group_id], parents, [d4h_group_id])

  defp climb(nil, _parents, _seen), do: []

  defp climb(id, parents, seen) do
    if id in seen, do: [], else: [id | climb(parents[id], parents, [id | seen])]
  end

  @doc "Pure. True when the group may start from `parent`: not itself, and no loop."
  def can_start_from?(d4h_group_id, parent_d4h_group_id, parents),
    do:
      d4h_group_id != parent_d4h_group_id and
        d4h_group_id not in ancestors(parent_d4h_group_id, parents)
end
