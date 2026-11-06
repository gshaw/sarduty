defmodule Web.Components.Outbox do
  @moduledoc """
  The Outbox's list and one message (docs/outbox.md): a demo team's page
  (Web.OutboxLive) and dev's (Web.DevOutboxLive) draw these. A message's links work, so
  a reply link in a reminder opens the reply page as the member would.
  """
  use Web, :function_component

  import Web.Components.A
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

  # Like the email previews (Web.Components.EmailPreview), with the header a mail app
  # shows. The HTML is SAR Duty's own mailers', which escape what people typed, as the
  # previews show it; here its links work, so a reply link answers as the member.
  def outbox_message(assigns) do
    ~H"""
    <article id={"outbox-message-#{@message.id}"}>
      <h1 class="title">{title(@message)}</h1>
      <div class="email-preview outbox-message">
        <dl class="outbox-head">
          <dt>From</dt>
          <dd id="outbox-from">{@message.from || "SAR Duty"}</dd>
          <dt>To</dt>
          <dd id="outbox-to">{@message.to}</dd>
          <dt :if={@message.kind == :email}>Subject</dt>
          <dd :if={@message.kind == :email}>{@message.subject}</dd>
          <dt>Date</dt>
          <dd>{Service.Format.month_day_time_seconds(@message.inserted_at, @timezone)}</dd>
          <dt :if={@message.attachments != []}>Attached</dt>
          <dd :if={@message.attachments != []} id="outbox-attachments">
            <%= for {attachment, index} <- Enum.with_index(@message.attachments) do %>
              {if index > 0, do: ", "}<.a
                id={"outbox-attachment-#{attachment.id}"}
                href={@attachment_path.(attachment)}
                external={true}
              >{attachment.filename}</.a>
            <% end %>
          </dd>
        </dl>
        <div :if={@message.html_body} id="outbox-html" class="email-preview-body">
          {Phoenix.HTML.raw(@message.html_body)}
        </div>
        <%!-- pre-wrap shows every space, so the text touches the tags: no indent or gap --%>
        <div
          :if={!@message.html_body && @message.body}
          id="outbox-body"
          class="email-preview-body whitespace-pre-wrap break-words"
          phx-no-format
        ><.linked_text text={String.trim(@message.body)} /></div>
      </div>
    </article>
    """
  end

  # The subject, or a text's first line.
  defp title(%OutboxMessage{kind: :email, subject: subject}), do: subject || "(no subject)"

  defp title(%OutboxMessage{kind: :text, body: body}),
    do: "Text: " <> (body |> String.split("\n", parts: 2) |> hd())

  attr :text, :string, required: true

  # Plain text with its web addresses as links, so a reply link can be followed.
  defp linked_text(assigns) do
    assigns = assign(assigns, :parts, split_links(assigns.text))

    # One line: the body is pre-wrap, so any space here would show.
    ~H"""
    <span phx-no-format><%= for {kind, part} <- @parts do %><.a :if={kind == :link} href={part}>{part}</.a><span :if={kind == :text}>{part}</span><% end %></span>
    """
  end

  @link ~r{https?://[^\s<>"]+}

  @doc false
  def split_links(text) do
    @link
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(&if(Regex.match?(~r{\Ahttps?://}, &1), do: {:link, &1}, else: {:text, &1}))
  end
end
