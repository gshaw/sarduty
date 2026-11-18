defmodule App.Repo.Migrations.CreateAiDrafts do
  use Ecto.Migration

  # Saved AI turns (#1089): a draft for each person and each report or form, kept after
  # every ask and every hand edit on Change report and Change form, with the
  # conversation. A team's report or form, or an organization's form; a new report has
  # no report yet. Its new PDFs are in the file store, under `files_token`.
  def change do
    create table(:ai_drafts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :team_id, references(:teams, on_delete: :delete_all)
      add :organization_id, references(:organizations, on_delete: :delete_all)
      add :kind, :string, null: false
      add :report_id, references(:reports, on_delete: :delete_all)
      add :form_id, references(:forms, on_delete: :delete_all)
      add :fields, :map, null: false
      add :asks, :map, null: false
      add :files_token, :string
      add :pages, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ai_drafts, [:user_id, :form_id], where: "form_id IS NOT NULL")
    create unique_index(:ai_drafts, [:user_id, :report_id], where: "report_id IS NOT NULL")

    create unique_index(:ai_drafts, [:user_id, :team_id],
             where: "kind = 'report' AND report_id IS NULL",
             name: :ai_drafts_new_report_index
           )

    create index(:ai_drafts, [:updated_at])
  end
end
