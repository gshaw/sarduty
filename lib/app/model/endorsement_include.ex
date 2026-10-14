defmodule App.Model.EndorsementInclude do
  use App, :model

  alias App.Model.Endorsement
  alias App.Model.EndorsementInclude
  alias App.Repo

  # One endorsement another includes: anything that earns `included_endorsement` earns
  # `endorsement` too (#326). Both belong to the same team.
  schema "endorsement_includes" do
    belongs_to :endorsement, Endorsement
    belongs_to :included_endorsement, Endorsement
    timestamps(type: :utc_datetime_usec)
  end

  def insert!(
        %Endorsement{team_id: team_id} = endorsement,
        %Endorsement{team_id: team_id} = other
      ) do
    %EndorsementInclude{endorsement_id: endorsement.id, included_endorsement_id: other.id}
    |> Repo.insert!(on_conflict: :nothing)
  end

  def delete!(%Endorsement{} = endorsement, included_endorsement_id) do
    EndorsementInclude
    |> where([ei], ei.endorsement_id == ^endorsement.id)
    |> where([ei], ei.included_endorsement_id == ^included_endorsement_id)
    |> Repo.delete_all()
  end

  @doc "Each of the team's endorsement ids with the ids it includes directly."
  def included_ids_by_endorsement(team_id) do
    EndorsementInclude
    |> join(:inner, [ei], e in assoc(ei, :endorsement))
    |> where([ei, e], e.team_id == ^team_id)
    |> select([ei], {ei.endorsement_id, ei.included_endorsement_id})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
