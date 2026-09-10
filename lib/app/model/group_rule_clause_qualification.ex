defmodule App.Model.GroupRuleClauseQualification do
  use App, :model

  alias App.Model.Group
  alias App.Model.GroupRuleClause
  alias App.Model.GroupRuleClauseQualification
  alias App.Repo

  schema "group_rule_clause_qualifications" do
    belongs_to :group_rule_clause, GroupRuleClause
    field :d4h_qualification_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}),
    do: build_changeset(%GroupRuleClauseQualification{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :group_rule_clause_id,
      :d4h_qualification_id
    ])
    |> validate_required([
      :group_rule_clause_id,
      :d4h_qualification_id
    ])
    |> unique_constraint([:group_rule_clause_id, :d4h_qualification_id])
  end

  def insert!(params) do
    changeset = GroupRuleClauseQualification.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def find!(%Group{} = group, id) do
    query =
      from(cq in GroupRuleClauseQualification,
        join: c in assoc(cq, :group_rule_clause),
        where: cq.id == ^id,
        where: c.team_id == ^group.team_id and c.d4h_group_id == ^group.d4h_group_id
      )

    Repo.one!(query)
  end

  def delete!(%GroupRuleClauseQualification{} = record), do: Repo.delete!(record)
end
