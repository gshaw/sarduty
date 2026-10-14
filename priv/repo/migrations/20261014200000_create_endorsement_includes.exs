defmodule App.Repo.Migrations.CreateEndorsementIncludes do
  use Ecto.Migration

  # An endorsement can include another: anything that earns the included one earns it
  # too, so 7h First Aid includes 70h First Aid instead of listing its courses (#326).
  def change do
    create table(:endorsement_includes) do
      add :endorsement_id, references(:endorsements, on_delete: :delete_all), null: false

      add :included_endorsement_id, references(:endorsements, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:endorsement_includes, [:endorsement_id, :included_endorsement_id])
    create index(:endorsement_includes, [:included_endorsement_id])
  end
end
