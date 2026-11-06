defmodule Web.OutboxAttachmentController do
  use Web, :controller

  alias App.Model.DemoTeam
  alias App.Model.OutboxAttachment
  alias App.Model.OutboxMessage

  # A file an Outbox email carried (docs/outbox.md): a PDF or image opens in the browser,
  # as a mail app would show it; anything else, such as a wallet pass, downloads.

  @doc "A Try a demo team's, for its team admins. A real team has no Outbox."
  def show(conn, %{"id" => id, "attachment_id" => attachment_id}) do
    team = conn.assigns.current_team
    if !DemoTeam.demo?(team), do: raise(Web.Status.NotFound)
    send_attachment(conn, OutboxMessage.get(team, id), attachment_id)
  end

  @doc "Any message's, on dev's /dev/outbox."
  def dev(conn, %{"id" => id, "attachment_id" => attachment_id}),
    do: send_attachment(conn, OutboxMessage.get(:all, id), attachment_id)

  defp send_attachment(_conn, nil, _attachment_id), do: raise(Web.Status.NotFound)

  defp send_attachment(conn, message, attachment_id) do
    attachment = OutboxMessage.get_attachment(message, attachment_id)
    if !attachment, do: raise(Web.Status.NotFound)
    disposition = if OutboxAttachment.inline?(attachment), do: "inline", else: "attachment"

    conn
    |> put_resp_content_type(attachment.content_type, nil)
    |> put_resp_header(
      "content-disposition",
      ~s(#{disposition}; filename="#{String.replace(attachment.filename, ~s("), "")}")
    )
    |> send_resp(200, attachment.data)
  end
end
