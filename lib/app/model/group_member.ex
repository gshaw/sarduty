defmodule App.Model.GroupMember do
  use App, :model

  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Repo

  schema "group_members" do
    belongs_to :group, Group
    belongs_to :member, Member
    field :d4h_group_membership_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%GroupMember{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :group_id,
      :member_id,
      :d4h_group_membership_id
    ])
    |> validate_required([
      :group_id,
      :member_id,
      :d4h_group_membership_id
    ])
  end

  @doc """
  The ids of a group's D4H members, as a query. The group is looked up through the team,
  so another team's group id finds no one.
  """
  def member_ids_query(team_id, group_id) do
    from gm in GroupMember,
      join: g in assoc(gm, :group),
      where: gm.group_id == ^group_id and g.team_id == ^team_id,
      select: gm.member_id
  end

  @doc "member_ids_query/2 as a set, or nil for no group: no filter."
  def member_ids(_team_id, nil), do: nil

  def member_ids(team_id, group_id),
    do: team_id |> member_ids_query(group_id) |> Repo.all() |> MapSet.new()

  def get_by(params), do: Repo.get_by(GroupMember, params)

  def insert!(params) do
    changeset = GroupMember.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%GroupMember{} = record, params) do
    changeset = GroupMember.build_changeset(record, params)
    Repo.update!(changeset)
  end
end
