defmodule App.Model.GroupEndorsement do
  use App, :model

  alias App.Model.Endorsement
  alias App.Model.Group
  alias App.Model.GroupEndorsement
  alias App.Model.GroupParent
  alias App.Repo

  # One endorsement a group's rule requires. A member must hold every one to be in the
  # group. The group is by D4H id, so the rule survives the sync recreating the row.
  schema "group_endorsements" do
    belongs_to :team, App.Model.Team
    belongs_to :endorsement, Endorsement
    field :d4h_group_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def add!(%Group{} = group, %Endorsement{team_id: team_id} = endorsement)
      when team_id == group.team_id do
    %GroupEndorsement{
      team_id: group.team_id,
      d4h_group_id: group.d4h_group_id,
      endorsement_id: endorsement.id
    }
    |> Repo.insert!(on_conflict: :nothing)
  end

  def remove!(%Group{} = group, endorsement_id) do
    GroupEndorsement
    |> where([ge], ge.team_id == ^group.team_id and ge.d4h_group_id == ^group.d4h_group_id)
    |> where([ge], ge.endorsement_id == ^endorsement_id)
    |> Repo.delete_all()
  end

  @doc """
  A query for the D4H ids of the team's groups that have a rule: endorsements of their
  own, or another group they start from.
  """
  def ruled_d4h_group_ids_query(team_id) do
    GroupEndorsement
    |> where([ge], ge.team_id == ^team_id)
    |> select([ge], ge.d4h_group_id)
    |> union(^GroupParent.child_d4h_group_ids_query(team_id))
  end

  @doc "Each endorsement id with the D4H ids of the groups that require it."
  def d4h_group_ids_by_endorsement(team_id) do
    GroupEndorsement
    |> where([ge], ge.team_id == ^team_id)
    |> select([ge], {ge.endorsement_id, ge.d4h_group_id})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
