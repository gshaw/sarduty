defmodule App.Repo.Migrations.CreateMemberCheckIns do
  use Ecto.Migration

  # A team admin's record that they reached a member (#366). It restarts the member's
  # attendance clock and nothing else. `checked_in_on` is a day on the team's clock.
  def change do
    create table(:member_check_ins) do
      add :team_id, references(:teams), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :checked_in_on, :date, null: false
      add :note, :text
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:member_check_ins, [:team_id, :member_id, :checked_in_on])
  end
end
