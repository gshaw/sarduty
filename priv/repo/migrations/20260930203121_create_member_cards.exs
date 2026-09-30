defmodule App.Repo.Migrations.CreateMemberCards do
  use Ecto.Migration

  def change do
    create table(:member_cards) do
      add :team_id, references(:teams), null: false
      add :member_id, references(:members), null: false
      add :code, :string, null: false
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:member_cards, [:code])
    create index(:member_cards, [:team_id, :member_id])
  end
end
