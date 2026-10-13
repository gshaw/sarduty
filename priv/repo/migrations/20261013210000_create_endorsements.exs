defmodule App.Repo.Migrations.CreateEndorsements do
  use Ecto.Migration

  alias App.Operation.PlanEndorsements

  # Group rule clauses become endorsements, a team-level list that group rules and ID
  # cards share (#320). The clause tables stay for one release, so `down` only drops the
  # new tables.
  def up do
    create table(:endorsements) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :on_card, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:endorsements, [:team_id, :name])

    create table(:endorsement_qualifications) do
      add :endorsement_id, references(:endorsements, on_delete: :delete_all), null: false
      add :d4h_qualification_id, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:endorsement_qualifications, [:endorsement_id, :d4h_qualification_id])

    create table(:group_endorsements) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :d4h_group_id, :integer, null: false
      add :endorsement_id, references(:endorsements, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:group_endorsements, [:team_id, :d4h_group_id, :endorsement_id])
    create index(:group_endorsements, [:endorsement_id])

    flush()

    for [team_id] <- rows("SELECT DISTINCT team_id FROM group_rule_clauses", []) do
      move_team(team_id)
    end
  end

  def down do
    drop table(:group_endorsements)
    drop table(:endorsement_qualifications)
    drop table(:endorsements)
  end

  defp move_team(team_id) do
    qualification_ids =
      "SELECT cq.group_rule_clause_id, cq.d4h_qualification_id
       FROM group_rule_clause_qualifications cq
       JOIN group_rule_clauses c ON c.id = cq.group_rule_clause_id
       WHERE c.team_id = ?"
      |> rows([team_id])
      |> Enum.group_by(&Enum.at(&1, 0), &Enum.at(&1, 1))

    clauses =
      for [id, d4h_group_id, name, on_card] <-
            rows(
              "SELECT id, d4h_group_id, name, on_card FROM group_rule_clauses WHERE team_id = ?",
              [team_id]
            ) do
        %{
          id: id,
          d4h_group_id: d4h_group_id,
          name: name,
          on_card: on_card in [1, true],
          qualification_ids: Map.get(qualification_ids, id, [])
        }
      end

    titles = by_d4h_id("SELECT d4h_qualification_id, title FROM qualifications", team_id)
    group_titles = by_d4h_id("SELECT d4h_group_id, title FROM groups", team_id)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    for endorsement <- PlanEndorsements.plan(clauses, titles, group_titles) do
      [[id]] =
        rows(
          "INSERT INTO endorsements (team_id, name, on_card, inserted_at, updated_at)
           VALUES (?, ?, ?, ?, ?) RETURNING id",
          [team_id, endorsement.name, if(endorsement.on_card, do: 1, else: 0), now, now]
        )

      for q <- endorsement.qualification_ids do
        rows(
          "INSERT INTO endorsement_qualifications
           (endorsement_id, d4h_qualification_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
          [id, q, now, now]
        )
      end

      for g <- endorsement.d4h_group_ids do
        rows(
          "INSERT INTO group_endorsements
           (team_id, d4h_group_id, endorsement_id, inserted_at, updated_at)
           VALUES (?, ?, ?, ?, ?)",
          [team_id, g, id, now, now]
        )
      end
    end
  end

  defp by_d4h_id(sql, team_id),
    do: (sql <> " WHERE team_id = ?") |> rows([team_id]) |> Map.new(fn [id, t] -> {id, t} end)

  defp rows(sql, params), do: repo().query!(sql, params).rows
end
