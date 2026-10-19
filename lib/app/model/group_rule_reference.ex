defmodule App.Model.GroupRuleReference do
  use App, :model

  alias App.Model.Endorsement
  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Model.GroupRuleReference
  alias App.Repo

  # One group, endorsement, or standing (#366) in a rule, with exactly one set. The group is by
  # D4H id, not a foreign key: when D4H drops a group, the sync deletes its row, and the
  # rule must break rather than vanish.
  schema "group_rule_references" do
    belongs_to :group_rule, GroupRule
    belongs_to :endorsement, Endorsement
    field :d4h_group_id, :integer
    field :standing, Ecto.Enum, values: [:active, :away, :not_a_person]
    timestamps(type: :utc_datetime_usec)
  end

  @doc "Adds a group or endorsement of the rule's team to the rule."
  def add!(%GroupRule{team_id: team_id} = rule, %Group{team_id: team_id} = group),
    do: insert!(%GroupRuleReference{group_rule_id: rule.id, d4h_group_id: group.d4h_group_id})

  def add!(%GroupRule{team_id: team_id} = rule, %Endorsement{team_id: team_id} = endorsement),
    do: insert!(%GroupRuleReference{group_rule_id: rule.id, endorsement_id: endorsement.id})

  def add!(%GroupRule{kind: :standing} = rule, standing)
      when standing in [:active, :away, :not_a_person],
      do: insert!(%GroupRuleReference{group_rule_id: rule.id, standing: standing})

  defp insert!(reference), do: Repo.insert!(reference, on_conflict: :nothing)

  @doc "Removes the rule's reference with `id`, and the rule when that was its last."
  def remove!(%GroupRule{} = rule, id) do
    GroupRuleReference
    |> where([ref], ref.group_rule_id == ^rule.id and ref.id == ^id)
    |> Repo.delete_all()

    GroupRule.delete_empty([rule.id])
  end

  def target(%GroupRuleReference{standing: nil, d4h_group_id: nil, endorsement_id: id}),
    do: {:endorsement, id}

  def target(%GroupRuleReference{standing: nil, d4h_group_id: d4h_group_id}),
    do: {:group, d4h_group_id}

  def target(%GroupRuleReference{standing: standing}), do: {:standing, standing}
end
