defmodule Web.DevOutboxLive do
  use Web, :live_view_marketing_layout

  import Web.Components.Outbox

  alias App.Model.OutboxMessage

  # Dev's Outbox (docs/outbox.md): every email and text the server kept instead of
  # sending, newest first, login codes among them. Dev routes only.

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(App.PubSub, OutboxMessage.topic())
    {:ok, assign(socket, page_title: "Outbox", timezone: "America/Vancouver")}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    case OutboxMessage.get(:all, id) do
      nil -> {:noreply, push_navigate(socket, to: ~p"/dev/outbox")}
      message -> {:noreply, assign(socket, message: message, messages: nil)}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, message: nil, messages: OutboxMessage.list(:all))}

  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-2 py-6">
      <%= if @message do %>
        <p class="mb-4"><.a patch={~p"/dev/outbox"}>Outbox</.a></p>
        <.outbox_message message={@message} timezone={@timezone} />
      <% else %>
        <h1 class="title">Outbox</h1>
        <p class="lead">
          Email and texts this server kept instead of sending. Login codes are here.
        </p>
        <.button
          :if={@messages != []}
          id="outbox-empty"
          phx-click="empty"
          data-confirm="Empty the outbox?"
          class="mb-4"
        >
          Empty the outbox
        </.button>
        <.outbox_list
          id="outbox"
          messages={@messages}
          path={&~p"/dev/outbox/#{&1.id}"}
          timezone={@timezone}
        />
      <% end %>
    </div>
    """
  end

  def handle_event("empty", _params, socket) do
    OutboxMessage.delete_all(:all)
    {:noreply, assign(socket, messages: [])}
  end

  def handle_info({:outbox_message, _team_id}, %{assigns: %{message: nil}} = socket),
    do: {:noreply, assign(socket, messages: OutboxMessage.list(:all))}

  def handle_info({:outbox_message, _team_id}, socket), do: {:noreply, socket}
end
