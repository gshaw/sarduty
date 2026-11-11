defmodule App.Repo.Migrations.CreateSignRequests do
  use Ecto.Migration

  # A team admin asks a form's task leader to sign it (#993): the member asked, who asked
  # and when, and when and why it ended. One open request per form and activity; asking
  # again ends the last one. `title` is the PDF's, "Task report 26-06613", as the
  # request's email and For you to do say it.
  def change do
    create table(:sign_requests) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :activity_id, references(:activities, on_delete: :delete_all), null: false
      add :form_id, references(:forms, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :asked_by_id, references(:users, on_delete: :nilify_all)
      add :title, :string, null: false
      add :asked_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :ended_why, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sign_requests, [:activity_id, :form_id],
             where: "ended_at IS NULL",
             name: :sign_requests_open_index
           )

    create index(:sign_requests, [:team_id])
    create index(:sign_requests, [:member_id])
    create index(:sign_requests, [:form_id])
  end
end
