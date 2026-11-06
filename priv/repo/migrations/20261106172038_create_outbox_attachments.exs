defmodule App.Repo.Migrations.CreateOutboxAttachments do
  use Ecto.Migration

  # An Outbox email's files, kept so the Outbox can open them (#857), such as a tax
  # credit letter's PDF. They replace the names alone in outbox_messages.attachments.
  def change do
    create table(:outbox_attachments) do
      add :outbox_message_id, references(:outbox_messages, on_delete: :delete_all), null: false

      add :position, :integer, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :data, :binary, null: false
    end

    create index(:outbox_attachments, [:outbox_message_id, :position])

    alter table(:outbox_messages) do
      remove :attachments, :string
    end
  end
end
