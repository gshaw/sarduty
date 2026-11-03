defmodule App.Repo.Migrations.AddCodeToDemoTeams do
  use Ecto.Migration

  # Try a demo's emailed code (#857), in the link and typed: only its hash, when it went,
  # and wrong tries against it.
  def change do
    alter table(:demo_teams) do
      add :code_hash, :binary
      add :code_sent_at, :utc_datetime
      add :code_misses, :integer, default: 0, null: false
    end
  end
end
