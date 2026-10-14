defmodule App.Model.Endorsement do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Endorsement
  alias App.Model.EndorsementInclude
  alias App.Model.EndorsementQualification
  alias App.Model.Group
  alias App.Model.GroupEndorsement
  alias App.Model.Team
  alias App.Repo

  # A name and the qualifications that earn it: a member holding any one of them has the
  # endorsement. Group rules require endorsements, and ID cards list the ones a team
  # picks (#320). Names are unique within a team.
  #
  # It can include other endorsements, so anything that earns one of those earns it too
  # (#326). The loaders fill `included_ids` (direct) and `earned_by_ids`, every
  # qualification that earns it once the includes are followed.
  schema "endorsements" do
    belongs_to :team, Team
    has_many :endorsement_qualifications, EndorsementQualification, on_delete: :delete_all
    field :name, TrimmedString
    field :on_card, :boolean, default: false
    field :included_ids, {:array, :integer}, virtual: true, default: []
    field :earned_by_ids, {:array, :integer}, virtual: true
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

  @doc """
  Deletes the endorsement, its qualifications, its place in every group rule, and its
  includes either way.
  """
  def delete!(%Endorsement{} = endorsement) do
    Repo.transaction(fn ->
      GroupEndorsement |> where([ge], ge.endorsement_id == ^endorsement.id) |> Repo.delete_all()

      EndorsementInclude
      |> where(
        [ei],
        ei.endorsement_id == ^endorsement.id or ei.included_endorsement_id == ^endorsement.id
      )
      |> Repo.delete_all()

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
    |> List.wrap()
    |> expand(team_id)
    |> hd()
  end

  @doc "The team's endorsements with their qualifications, in name order."
  def get_all(team_id) do
    Endorsement
    |> where([e], e.team_id == ^team_id)
    |> preload(endorsement_qualifications: [])
    |> order_by([e], asc: e.name)
    |> Repo.all()
    |> expand(team_id)
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
    |> expand(team_id)
  end

  def get_all_for_group(%Group{} = group),
    do: get_all_for_group(group.team_id, group.d4h_group_id)

  @doc "Every qualification that earns it, following includes once a loader has."
  def qualification_ids(%{earned_by_ids: ids}) when is_list(ids), do: ids
  def qualification_ids(endorsement), do: own_qualification_ids(endorsement)

  @doc "The qualifications listed on the endorsement itself, not through an include."
  def own_qualification_ids(%{endorsement_qualifications: eqs}),
    do: Enum.map(eqs, & &1.d4h_qualification_id)

  # Fills `included_ids` and `earned_by_ids` from the team's includes and qualifications.
  defp expand([], _team_id), do: []

  defp expand(endorsements, team_id) do
    includes = EndorsementInclude.included_ids_by_endorsement(team_id)
    own = own_ids_by_endorsement(team_id)

    Enum.map(endorsements, fn endorsement ->
      %{
        endorsement
        | included_ids: Map.get(includes, endorsement.id, []),
          earned_by_ids: earned_by_ids(endorsement.id, own, includes)
      }
    end)
  end

  defp own_ids_by_endorsement(team_id) do
    EndorsementQualification
    |> join(:inner, [eq], e in assoc(eq, :endorsement))
    |> where([eq, e], e.team_id == ^team_id)
    |> order_by([eq], asc: eq.id)
    |> select([eq], {eq.endorsement_id, eq.d4h_qualification_id})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc """
  Pure. Every qualification that earns endorsement `id`: its own, then those of every
  endorsement it reaches through includes. `own` and `includes` are keyed by endorsement id.
  """
  def earned_by_ids(id, own, includes) do
    [id | id |> reachable_ids(includes) |> MapSet.delete(id) |> Enum.sort()]
    |> Enum.flat_map(&Map.get(own, &1, []))
    |> Enum.uniq()
  end

  @doc "Pure. Endorsement `id` and every one it reaches through includes."
  def reachable_ids(id, includes), do: walk([id], includes, MapSet.new())

  defp walk([], _includes, seen), do: seen

  defp walk([id | rest], includes, seen) do
    if MapSet.member?(seen, id),
      do: walk(rest, includes, seen),
      else: walk(Map.get(includes, id, []) ++ rest, includes, MapSet.put(seen, id))
  end

  @doc """
  Pure. True when `endorsement` may include `other`: not itself, and not one that already
  reaches it, which would make a loop.
  """
  def can_include?(endorsement_id, other_id, includes),
    do: not (other_id |> reachable_ids(includes) |> MapSet.member?(endorsement_id))

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
