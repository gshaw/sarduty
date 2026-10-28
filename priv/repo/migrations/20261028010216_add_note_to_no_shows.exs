defmodule App.Repo.Migrations.AddNoteToNoShows do
  use Ecto.Migration

  # What a team admin heard when they followed up a no-show, such as "sick, told the
  # trainer" (#650). Optional: the tick alone is enough.
  def change do
    alter table(:no_shows) do
      add :note, :text
    end
  end
end
