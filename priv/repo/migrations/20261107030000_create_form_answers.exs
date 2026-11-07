defmodule App.Repo.Migrations.CreateFormAnswers do
  use Ecto.Migration

  # What a team admin answered on an activity's forms (#950, step 4), shared by name
  # across forms and never sent to D4H. `row` is "" for one answer; step 7's `ask each`
  # keys a row by its member or item.
  def change do
    create table(:form_answers) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :activity_id, references(:activities, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :row, :string, null: false, default: ""
      add :value, :text, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:form_answers, [:activity_id, :name, :row])
    # `remember`: the team's last answer to a name.
    create index(:form_answers, [:team_id, :name, :updated_at])
  end
end
