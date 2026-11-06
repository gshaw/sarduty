defmodule Web.Components.Outbox do
  @moduledoc """
  The Outbox's list and one message (docs/outbox.md): a demo team's page
  (Web.OutboxLive) and dev's (Web.DevOutboxLive) draw these. A message's links work, so
  a reply link in a reminder opens the reply page as the member would.
  """
  use Web, :function_component

  import Web.Components.A
  import Web.Components.EmailPreview
  import Web.Components.Table

  alias App.Model.OutboxMessage

  attr :id, :string, required: true
  attr :messages, :list, required: true
  attr :path, :any, required: true, doc: "fn message -> its page"
  attr :timezone, :string, required: true
  attr :new?, :any, default: nil, doc: "fn message -> whether it says New; none when nil"

  def outbox_list(assigns) do
    ~H"""
    <p :if={@messages == []} id={"#{@id}-empty"}>Nothing yet.</p>
    <.table
      :if={@messages != []}
      id={@id}
      rows={@messages}
      row_id={&"outbox-message-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={message} label="Sent" class="whitespace-nowrap">
        {Service.Format.month_day_time(message.inserted_at, @timezone)}
      </:col>
      <:col :let={message} label="To">{message.to}</:col>
      <:col :let={message} label="Message">
        <.a navigate={@path.(message)}>{title(message)}</.a>
        <.badge :if={@new? && @new?.(message)} kind={:primary}>New</.badge>
      </:col>
    </.table>
    """
  end

  attr :message, OutboxMessage, required: true
  attr :timezone, :string, required: true
  attr :attachment_path, :any, required: true, doc: "fn attachment -> its file"

  # The email preview with a mail app's header (/styles/email-preview), wide, with its
  # links live, so a reply link answers as the member. The HTML is SAR Duty's own
  # mailers', which escape what people typed.
  def outbox_message(assigns) do
    ~H"""
    <article id={"outbox-message-#{@message.id}"}>
      <h1 class="title">{title(@message)}</h1>
      <.email_preview
        id="outbox"
        width={:wide}
        live
        from={@message.from}
        to={@message.to}
        subject={@message.kind == :email && @message.subject}
        date={Service.Format.month_day_time_seconds(@message.inserted_at, @timezone)}
        html={@message.html_body}
        text={@message.body}
        attachments={
          for attachment <- @message.attachments,
              do: %{
                id: attachment.id,
                name: attachment.filename,
                size: attachment.size,
                href: @attachment_path.(attachment)
              }
        }
      />
    </article>
    """
  end

  # The subject, or a text's first line.
  defp title(%OutboxMessage{kind: :email, subject: subject}), do: subject || "(no subject)"

  defp title(%OutboxMessage{kind: :text, body: body}),
    do: "Text: " <> (body |> String.split("\n", parts: 2) |> hd())
end
