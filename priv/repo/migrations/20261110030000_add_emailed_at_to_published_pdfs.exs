defmodule App.Repo.Migrations.AddEmailedAtToPublishedPdfs do
  use Ecto.Migration

  # When a letter's email last went (#970), for its History and the letters list. Letters
  # emailed before this have none: History shows them as Emailed with no time.
  def change do
    alter table(:published_pdfs) do
      add :emailed_at, :utc_datetime_usec
    end
  end
end
