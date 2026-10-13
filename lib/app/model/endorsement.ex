defmodule App.Model.Endorsement do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.Model.Group
  alias App.Model.GroupEndorsement
  alias App.Model.Team
  alias App.Repo

  # A name and the qualifications that earn it: a member holding any one of them has the
  # endorsement. Group rules require endorsements, and ID cards list the ones a team
  # picks (#320). Names are unique within a team.
  schema "endorsements" do
    belongs_to :team, Team
    has_many :endorsement_qualifications, EndorsementQualification, on_delete: :delete_all
    field :name, TrimmedString
    field :on_card, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 60)
    |> unique_constraint([:team_id, :name], message: "is already an endorsement")
  end

  def insert(%Team{} = team, params),
    do: %Endorsement{team_id: team.id} |> build_changeset(params) |> Repo.insert()

  def rename(%Endorsement{} = endorsement, params),
    do: endorsement |> build_changeset(params) |> Repo.update()

  @doc "Deletes the endorsement, its qualifications, and its place in every group rule."
  def delete!(%Endorsement{} = endorsement) do
    Repo.transaction(fn ->
      GroupEndorsement |> where([ge], ge.endorsement_id == ^endorsement.id) |> Repo.delete_all()

      EndorsementQualification
      |> where([eq], eq.endorsement_id == ^endorsement.id)
      |> Repo.delete_all()

      Repo.delete!(endorsement)
    end)
  end

  def get!(team_id, id) do
    Endorsement
    |> where([e], e.team_id == ^team_id and e.id == ^id)
    |> preload(endorsement_qualifications: [])
    |> Repo.one!()
  end

  @doc "The team's endorsements with their qualifications, in name order."
  def get_all(team_id) do
    Endorsement
    |> where([e], e.team_id == ^team_id)
    |> preload(endorsement_qualifications: [])
    |> order_by([e], asc: e.name)
    |> Repo.all()
  end

  @doc "The endorsements a group's rule requires, in the order they were added."
  def get_all_for_group(team_id, d4h_group_id) do
    Endorsement
    |> join(:inner, [e], ge in GroupEndorsement, on: ge.endorsement_id == e.id)
    |> where([e, ge], e.team_id == ^team_id and ge.team_id == ^team_id)
    |> where([e, ge], ge.d4h_group_id == ^d4h_group_id)
    |> preload(endorsement_qualifications: [])
    |> order_by([e, ge], asc: ge.id)
    |> Repo.all()
  end

  def get_all_for_group(%Group{} = group),
    do: get_all_for_group(group.team_id, group.d4h_group_id)

  def qualification_ids(%{endorsement_qualifications: eqs}),
    do: Enum.map(eqs, & &1.d4h_qualification_id)

  @doc "Lists the endorsements with `ids` on ID cards, and takes the rest off."
  def set_on_card!(team_id, ids) do
    Repo.transaction(fn ->
      Endorsement |> where([e], e.team_id == ^team_id) |> Repo.update_all(set: [on_card: false])

      Endorsement
      |> where([e], e.team_id == ^team_id and e.id in ^ids)
      |> Repo.update_all(set: [on_card: true])
    end)
  end
end
