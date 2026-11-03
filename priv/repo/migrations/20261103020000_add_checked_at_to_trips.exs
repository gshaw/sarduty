defmodule App.Repo.Migrations.AddCheckedAtToTrips do
  use Ecto.Migration

  # When the member said a trip is right or changed it themselves (#230). A team admin
  # setting it again clears it, so the member checks the new one.
  def change do
    alter table(:trips) do
      add :checked_at, :utc_datetime
    end

    create index(:trips, [:member_id, :checked_at])
  end
end
