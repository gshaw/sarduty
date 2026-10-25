defmodule App.Model.GroupRule do
  use App, :model

  alias App.Model.Endorsement
  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Model.GroupRuleReference
  alias App.Repo

  # One thing a member must meet to be in a group (#334): in any of some groups and
  # endorsements, in none of them, or any of some standings (#366). A group's members must
  # meet every one of its rules. The group is by D4H id, so its rules survive the sync
  # recreating its row.
  schema "group_rules" do
    belongs_to :team, App.Model.Team
    has_many :references, GroupRuleReference, on_delete: :delete_all
    field :d4h_group_id, :integer
    field :kind, Ecto.Enum, values: [:in, :not_in, :standing]
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  A new rule on `group` with one group or endorsement in it, or for `:standing`, one
  standing: `:active`, `:away`, or `:not_a_person`.
  """
  def add!(%Group{} = group, kind, target) when kind in [:in, :not_in, :standing] do
    Repo.transaction(fn ->
      rule =
        Repo.insert!(%GroupRule{
          team_id: group.team_id,
          d4h_group_id: group.d4h_group_id,
          kind: kind
        })

      GroupRuleReference.add!(rule, target)
      rule
    end)
  end

  def delete!(%GroupRule{} = rule), do: Repo.delete!(rule)

  @doc "The group's rule with `id`, looked up through the group and so its team."
  def find!(%Group{} = group, id) do
    GroupRule
    |> where([r], r.id == ^id and r.team_id == ^group.team_id)
    |> where([r], r.d4h_group_id == ^group.d4h_group_id)
    |> preload(:references)
    |> Repo.one!()
  end

  @doc "The team's rules with their references, in the order they were added."
  def get_all(team_id) do
    GroupRule
    |> where([r], r.team_id == ^team_id)
    |> order_by([r], asc: r.id)
    |> preload(references: ^from(ref in GroupRuleReference, order_by: ref.id))
    |> Repo.all()
  end

  @doc "Each D4H group id with its rules, from `get_all/1`."
  def by_group(rules), do: Enum.group_by(rules, & &1.d4h_group_id)

  @doc "A query for the D4H ids of the team's groups that have rules."
  def ruled_d4h_group_ids_query(team_id) do
    GroupRule
    |> where([r], r.team_id == ^team_id)
    |> select([r], r.d4h_group_id)
    |> distinct(true)
  end

  @doc "Whether the group has rules. A group without them is a list kept by hand."
  def ruled?(%Group{} = group) do
    GroupRule
    |> where([r], r.team_id == ^group.team_id and r.d4h_group_id == ^group.d4h_group_id)
    |> Repo.exists?()
  end

  @doc "Takes the endorsement out of every rule, and deletes a rule it leaves empty."
  def remove_endorsement!(%Endorsement{} = endorsement) do
    rule_ids =
      GroupRuleReference
      |> where([ref], ref.endorsement_id == ^endorsement.id)
      |> select([ref], ref.group_rule_id)
      |> Repo.all()

    GroupRuleReference |> where([ref], ref.endorsement_id == ^endorsement.id) |> Repo.delete_all()
    delete_empty(rule_ids)
  end

  @doc "Deletes the rules with `ids` that have no references left."
  def delete_empty(ids) do
    GroupRule
    |> where([r], r.id in ^ids)
    |> where([r], r.id not in subquery(select(GroupRuleReference, [ref], ref.group_rule_id)))
    |> Repo.delete_all()
  end

  @doc """
  Pure. The rule's references as `{:group, d4h_group_id}`, `{:endorsement, id}`, or
  `{:standing, standing}`.
  """
  def targets(%GroupRule{references: references}),
    do: Enum.map(references, &GroupRuleReference.target/1)

  @doc """
  Pure. The D4H ids of the groups whose rules name group `d4h_group_id`. `rules` is
  each D4H group id with its rules, each with `targets`.
  """
  def used_by(rules, d4h_group_id) do
    for {g, rs} <- rules,
        Enum.any?(rs, &({:group, d4h_group_id} in &1.targets)),
        do: g
  end

  @doc """
  Pure. True when group `d4h_group_id` may name group `other`: not itself, and not a
  group whose rules lead back to it, which would make a loop.
  """
  def can_name?(rules, d4h_group_id, other),
    do: not (other |> reachable(rules, MapSet.new()) |> MapSet.member?(d4h_group_id))

  defp reachable(g, rules, seen) do
    if MapSet.member?(seen, g) do
      seen
    else
      rules
      |> Map.get(g, [])
      |> Enum.flat_map(& &1.targets)
      |> Enum.reduce(MapSet.put(seen, g), fn
        {:group, next}, seen -> reachable(next, rules, seen)
        _target, seen -> seen
      end)
    end
  end
end
