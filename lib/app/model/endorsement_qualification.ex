defmodule App.Model.EndorsementQualification do
  use App, :model

  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.Repo

  # One qualification that earns an endorsement, by D4H id so it survives the sync
  # recreating the local row.
  schema "endorsement_qualifications" do
    belongs_to :endorsement, Endorsement
    field :d4h_qualification_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def insert!(%Endorsement{} = endorsement, d4h_qualification_id) do
    %EndorsementQualification{
      endorsement_id: endorsement.id,
      d4h_qualification_id: d4h_qualification_id
    }
    |> Repo.insert!(on_conflict: :nothing)
  end

  def find!(%Endorsement{} = endorsement, id),
    do: Repo.get_by!(EndorsementQualification, id: id, endorsement_id: endorsement.id)

  def delete!(%EndorsementQualification{} = record), do: Repo.delete!(record)
end
