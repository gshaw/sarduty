defmodule App.Repo.Migrations.CreateQualificationsAndMemberQualificationAwards do
  use Ecto.Migration

  def change do
    create table(:qualifications) do
      add :team_id, references(:teams), null: false
      add :d4h_qualification_id, :integer, null: false
      add :title, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:qualifications, [:team_id, :d4h_qualification_id])

    create table(:member_qualification_awards) do
      add :member_id, references(:members), null: false
      add :qualification_id, references(:qualifications), null: false
      add :d4h_award_id, :integer, null: false
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:member_qualification_awards, [:member_id, :d4h_award_id])
  end
end
