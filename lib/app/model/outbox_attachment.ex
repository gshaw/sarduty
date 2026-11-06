defmodule App.Model.OutboxAttachment do
  use App, :model

  alias App.Model.OutboxMessage

  # A file an Outbox email carried (docs/outbox.md), such as a tax credit letter's PDF,
  # so the Outbox opens it as the member's mail app would.
  schema "outbox_attachments" do
    belongs_to :outbox_message, OutboxMessage
    field :position, :integer
    field :filename, :string, redact: true
    field :content_type, :string
    field :data, :binary, redact: true
    field :size, :integer, virtual: true
  end

  @doc "The attachments of a Swoosh email, in order, ready to insert with its message."
  def from_email(%Swoosh.Email{attachments: attachments}) do
    attachments
    |> Enum.with_index()
    |> Enum.map(fn {attachment, position} ->
      %__MODULE__{
        position: position,
        filename: attachment.filename,
        content_type: attachment.content_type || "application/octet-stream",
        data: attachment.data || File.read!(attachment.path)
      }
    end)
  end

  @doc "Whether a browser shows it in place rather than downloading it."
  def inline?(%__MODULE__{content_type: type}),
    do: type == "application/pdf" or String.starts_with?(type, "image/")
end
