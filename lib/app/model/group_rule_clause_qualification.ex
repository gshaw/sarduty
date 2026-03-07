defmodule App.Model.GroupRuleClauseQualification do
  use App, :model

  alias App.Model.GroupRuleClause
  alias App.Model.GroupRuleClauseQualification
  alias App.Repo

  schema "group_rule_clause_qualifications" do
    belongs_to :group_rule_clause, GroupRuleClause
    field :d4h_qualification_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%GroupRuleClauseQualification{}, params)

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

  def delete!(id) do
    Repo.get!(GroupRuleClauseQualification, id) |> Repo.delete!()
  end
end
