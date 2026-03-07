defmodule App.Model.GroupRuleClause do
  use App, :model

  alias App.Model.GroupRuleClause
  alias App.Model.GroupRuleClauseQualification
  alias App.Model.Team
  alias App.Repo

  schema "group_rule_clauses" do
    belongs_to :team, Team
    has_many :group_rule_clause_qualifications, GroupRuleClauseQualification, on_delete: :delete_all
    field :d4h_group_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%GroupRuleClause{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :team_id,
      :d4h_group_id
    ])
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

  def delete!(id) do
    Repo.get!(GroupRuleClause, id) |> Repo.delete!()
  end
end
