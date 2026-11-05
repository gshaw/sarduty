defmodule Web.OutboxLive do
  use Web, :live_view_app_layout

  import Web.Components.Outbox

  alias App.Model.DemoTeam
  alias App.Model.OutboxMessage

  # A Try a demo team's Outbox (#857, docs/outbox.md): every email the demo would have
  # sent, kept here instead, newest first. The banner links it. A real team has none.

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !DemoTeam.demo?(team), do: raise(Web.Status.NotFound)
    # The demo banner's hook subscribes for its team admins (Web.UserAuth); anyone else here
    # is a site admin, who subscribes for themselves.
    if connected?(socket) and is_nil(socket.assigns[:demo]),
      do: Phoenix.PubSub.subscribe(App.PubSub, OutboxMessage.topic())

    {:ok, assign(socket, page_title: "Outbox")}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    team = socket.assigns.current_team

    case OutboxMessage.get(team, id) do
      nil ->
        raise Web.Status.NotFound

      message ->
        {:noreply, assign(socket, message: message, messages: nil, page_title: "Outbox · #{id}")}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, message: nil, messages: list(socket))}

  defp list(socket), do: OutboxMessage.list(socket.assigns.current_team)

  def render(assigns) do
    ~H"""
    <%= if @message do %>
      <.breadcrumbs>
        <:item label="Outbox" path={~p"/teams/#{@current_team}/outbox"} />
        <:item label="Message" />
      </.breadcrumbs>
      <.outbox_message
        message={@message}
        timezone={@current_team.timezone}
      />
    <% else %>
      <h1 class="title">Outbox</h1>
      <p class="lead max-w-3xl">
        Every email and text this demo would have sent, newest first. On a real team these
        go to members' inboxes and phones; a demo keeps them here, so nothing reaches anyone.
      </p>
      <p class="max-w-3xl mb-6">
        Send a reminder or an update from an activity, remove a member, or email a tax credit
        letter or an ID card, and the message shows up here at once, one for each member.
        Its links work: open a reminder's reply link to answer as that member.
      </p>
      <.outbox_list
        id="outbox"
        messages={@messages}
        path={&~p"/teams/#{@current_team}/outbox/#{&1.id}"}
        timezone={@current_team.timezone}
      />
    <% end %>
    """
  end

  def handle_info({:outbox_message, team_id}, %{assigns: %{message: nil}} = socket) do
    if team_id == socket.assigns.current_team.id,
      do: {:noreply, assign(socket, messages: list(socket))},
      else: {:noreply, socket}
  end

  def handle_info({:outbox_message, _team_id}, socket), do: {:noreply, socket}
end
