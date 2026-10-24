defmodule App.Repo.Migrations.CreateCertificates do
  use Ecto.Migration

  # A member's certificate for a qualification (#493), waiting for a team admin. The file
  # is in its own table, so lists never load it, and is deleted once the certificate is
  # accepted into D4H or declined. Certificates hide behind a team setting, off for every
  # team.
  def change do
    alter table(:teams) do
      add :certificates_enabled, :boolean, null: false, default: false
    end

    create table(:certificates) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :qualification_id, references(:qualifications, on_delete: :nilify_all)
      add :starts_on, :date, null: false
      add :ends_on, :date
      add :status, :string, null: false, default: "waiting"
      add :file_name, :string, null: false
      add :content_type, :string, null: false
      add :file_size, :integer, null: false
      add :decline_reason, :text
      add :decided_by_user_id, references(:users, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec
      add :change_set_id, references(:change_sets, on_delete: :nilify_all)
      add :d4h_award_id, :integer
      add :d4h_document_id, :integer
      timestamps(type: :utc_datetime_usec)
    end

    create index(:certificates, [:team_id, :status])
    create index(:certificates, [:member_id])

    create table(:certificate_files) do
      add :certificate_id, references(:certificates, on_delete: :delete_all), null: false
      add :bytes, :binary, null: false
    end

    create unique_index(:certificate_files, [:certificate_id])
  end
end
