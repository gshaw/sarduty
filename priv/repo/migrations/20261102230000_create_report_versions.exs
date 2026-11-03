defmodule App.Repo.Migrations.CreateReportVersions do
  use Ecto.Migration

  # Report versions (#834): every save of a team's own report appends a row, never
  # changed after. Picked values stay out: they can hold a member's ID. A deleted report
  # keeps its versions for 30 days under Recently deleted (`reports.deleted_at`), then a
  # nightly job deletes both. Each report saved before this gets its current text as its
  # first version, from its last save.
  def up do
    alter table(:reports) do
      add :deleted_at, :utc_datetime
    end

    create table(:report_versions) do
      add :report_id, references(:reports, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :about, :string
      add :query, :text, null: false
      add :change, :string
      add :user_id, references(:users, on_delete: :nilify_all)
      add :agent, :string
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:report_versions, [:report_id])
    create index(:report_versions, [:user_id])

    execute """
    INSERT INTO report_versions (report_id, name, about, query, user_id, agent, inserted_at)
    SELECT id, name, about, query, created_by_user_id, agent, updated_at FROM reports
    """
  end

  def down do
    drop table(:report_versions)

    alter table(:reports) do
      remove :deleted_at
    end
  end
end
