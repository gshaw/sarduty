defmodule App.Repo.Migrations.AddAddedByToTeamLoginGrants do
  use Ecto.Migration

  # Login grants are added on a team's SAR Duty admin page now (#513), so keep who added
  # each, as organization admins do. Grants added from the console have none.
  def change do
    alter table(:team_login_grants) do
      add :added_by_user_id, references(:users, on_delete: :nilify_all)
    end
  end
end
