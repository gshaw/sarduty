defmodule App.Repo.Migrations.CreateOutboxMessages do
  use Ecto.Migration

  # The Outbox: email and texts kept instead of sent. A Try a demo team's, always (#857),
  # and everything in dev, where the server has no email or Twilio set up.
  def change do
    create table(:outbox_messages) do
      add :team_id, references(:teams, on_delete: :delete_all)
      add :kind, :string, null: false
      add :from, :string
      add :to, :string, null: false
      add :subject, :string
      add :body, :text
      add :html_body, :text
      add :attachments, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:outbox_messages, [:team_id, :inserted_at])
  end
end
