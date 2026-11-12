defmodule App.Repo.Migrations.AddSignedByToPublishedPdfs do
  use Ecto.Migration

  # Who signed a form's PDF, and whom for when a team admin signed for its task leader
  # (#993), as their names printed: the Published box and History say "Signed by Alex
  # Chen for Cameron Ruiz". A letter, and a form published before this, have neither.
  def change do
    alter table(:published_pdfs) do
      add :signed_by, :string
      add :signed_for, :string
    end
  end
end
