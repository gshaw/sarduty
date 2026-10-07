defmodule App.Repo.Migrations.AddSignerDetailsToTeams do
  use Ecto.Migration

  # Printed under the signer's name on tax credit letters (#193). All optional.
  def change do
    alter table(:teams) do
      add :authorized_by_title, :string
      add :authorized_by_phone, :string
      add :authorized_by_email, :string
    end
  end
end
