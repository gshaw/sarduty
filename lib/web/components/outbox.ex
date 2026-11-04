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
      </:col>
    </.table>
    """
  end

  attr :message, OutboxMessage, required: true
  attr :html_path, :string, required: true
  attr :timezone, :string, required: true

  def outbox_message(assigns) do
    ~H"""
    <article id={"outbox-message-#{@message.id}"}>
      <h1 class="title">{title(@message)}</h1>
      <dl class="mb-6">
        <dt>{if @message.kind == :text, do: "Text to", else: "To"}</dt>
        <dd id="outbox-to">{@message.to}</dd>
        <dt>Sent</dt>
        <dd>{Service.Format.month_day_time_seconds(@message.inserted_at, @timezone)}</dd>
        <dt :if={@message.attachments}>Attached</dt>
        <dd :if={@message.attachments}>{@message.attachments}</dd>
      </dl>
      <iframe
        :if={@message.html_body}
        id="outbox-html"
        src={@html_path}
        title={title(@message)}
        sandbox="allow-popups allow-popups-to-escape-sandbox allow-top-navigation-by-user-activation"
        class="outbox-frame"
      ></iframe>
      <div :if={@message.body} id="outbox-body" class="whitespace-pre-wrap break-words max-w-3xl">
        <.linked_text text={@message.body} />
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

    ~H"""
    <%= for {kind, part} <- @parts do %>
      <.a :if={kind == :link} href={part}>{part}</.a><span :if={kind == :text}>{part}</span>
    <% end %>
    """
  end

  @link ~r{https?://[^\s<>"]+}

  @doc false
  def split_links(text) do
    @link
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(&if(Regex.match?(~r{\Ahttps?://}, &1), do: {:link, &1}, else: {:text, &1}))
  end

  @doc """
  The HTML version's own response: no script, no forms, styles and images only. The
  page shows it in a sandboxed frame, so an email's HTML never runs as SAR Duty.
  """
  def send_html(conn, %OutboxMessage{html_body: html}) when is_binary(html) do
    conn
    |> Plug.Conn.put_resp_header(
      "content-security-policy",
      "sandbox allow-popups allow-popups-to-escape-sandbox allow-top-navigation-by-user-activation; default-src 'none'; style-src 'unsafe-inline'; img-src https: data:"
    )
    |> Plug.Conn.delete_resp_header(Web.CSP.header())
    |> Phoenix.Controller.html(html)
  end
end
