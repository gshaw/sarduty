defmodule App.Repo.Migrations.AddCertificateNote do
  use Ecto.Migration

  # A member's note for the team admin, such as which course a certificate is for, when
  # they are not sure of the qualification (#493).
  def change do
    alter table(:certificates) do
      add :note, :text
    end
  end
end
