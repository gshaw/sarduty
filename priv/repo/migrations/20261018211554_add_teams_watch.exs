defmodule App.Repo.Migrations.AddTeamsWatch do
  use Ecto.Migration

  # The attendance check watches one group and some standings (#366). Nil is all current
  # members, and a group is by D4H id, like group rules, so a group D4H drops shows as a
  # warning instead of quietly watching everyone. Existing teams watch all members who
  # are active, with their time frame as it was.
  def change do
    alter table(:teams) do
      add :watch_d4h_group_id, :integer
      add :watch_standings, {:array, :string}, null: false, default: ~s(["active"])
    end
  end
end
