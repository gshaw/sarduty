defmodule App.Model.GroupRuleClause do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Group
  alias App.Model.GroupRuleClause
  alias App.Model.GroupRuleClauseQualification
  alias App.Model.Team
  alias App.Repo

  schema "group_rule_clauses" do
    belongs_to :team, Team

    has_many :group_rule_clause_qualifications, GroupRuleClauseQualification,
      on_delete: :delete_all

    field :d4h_group_id, :integer
    field :name, TrimmedString
    # Named clauses a team picked to list on the back of member ID cards.
    field :on_card, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%GroupRuleClause{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :team_id,
      :d4h_group_id,
      :name
    ])
    |> validate_length(:name, max: 60)
    |> validate_required([
      :team_id,
      :d4h_group_id
    ])
  end

  def get_all_for_group(team_id, d4h_group_id) do
    GroupRuleClause
    |> where([c], c.team_id == ^team_id and c.d4h_group_id == ^d4h_group_id)
    |> preload(group_rule_clause_qualifications: [])
    |> order_by([c], asc: c.id)
    |> Repo.all()
  end

  def insert!(params) do
    changeset = GroupRuleClause.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def find!(%Group{} = group, id) do
    Repo.get_by!(GroupRuleClause,
      id: id,
      team_id: group.team_id,
      d4h_group_id: group.d4h_group_id
    )
  end

  def rename(%GroupRuleClause{} = clause, name) do
    clause
    |> build_changeset(%{name: name})
    |> Repo.update()
  end

  def delete!(%GroupRuleClause{} = clause), do: Repo.delete!(clause)

  @doc "The team's named clauses with their qualifications, in name order."
  def get_all_named(team_id) do
    GroupRuleClause
    |> where([c], c.team_id == ^team_id and not is_nil(c.name) and c.name != "")
    |> preload(group_rule_clause_qualifications: [])
    |> order_by([c], asc: c.name, asc: c.id)
    |> Repo.all()
  end

  @doc "Shows every clause with one of `names` on ID cards, and hides the rest."
  def set_on_card!(team_id, names) do
    GroupRuleClause
    |> where([c], c.team_id == ^team_id)
    |> Repo.update_all(set: [on_card: false])

    GroupRuleClause
    |> where([c], c.team_id == ^team_id and c.name in ^names)
    |> Repo.update_all(set: [on_card: true])
  end
end
