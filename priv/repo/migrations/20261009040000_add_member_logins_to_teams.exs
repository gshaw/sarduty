defmodule App.Repo.Migrations.AddMemberLoginsToTeams do
  use Ecto.Migration

  # A team admin's switch that lets every current member log in for their own ID card
  # and tax credit letters (#156). Off until a team turns it on.
  def change do
    alter table(:teams) do
      add :member_logins, :boolean, null: false, default: false
    end
  end
end
