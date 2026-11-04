defmodule Web.OutboxController do
  use Web, :controller

  alias App.Model.DemoTeam
  alias App.Model.OutboxMessage
  alias Web.Components.Outbox

  # An Outbox email's HTML, on its own, for the sandboxed frame on its page
  # (Web.Components.Outbox): dev's, and a demo team's for its team admins.

  def dev_html(conn, %{"id" => id}), do: send_html(conn, OutboxMessage.get(:all, id))

  def team_html(conn, %{"id" => id}) do
    team = conn.assigns.current_team
    if !DemoTeam.demo?(team), do: raise(Web.Status.NotFound)
    send_html(conn, OutboxMessage.get(team, id))
  end

  defp send_html(conn, %OutboxMessage{html_body: html} = message) when is_binary(html),
    do: Outbox.send_html(conn, message)

  defp send_html(_conn, _none), do: raise(Web.Status.NotFound)
end
