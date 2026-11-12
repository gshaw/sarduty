defmodule Web.Admin.AdminCollectionLive do
  use Web, :live_view_app_layout

  alias App.Accounts
  alias App.Accounts.UserPasskey
  alias App.Model.Team

  def mount(_params, _session, socket) do
    admins = Accounts.get_admins()
    teams = Map.new(Team.get_all(), &{&1.id, &1})

    socket =
      socket
      |> assign(page_title: "Admins", admins: admins, teams: teams)
      |> assign(passkeys: UserPasskey.count_by_user())

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">Admins</h1>
    <p class="max-w-prose">
      Admins can open every team, refresh any team from D4H, and set up organizations. Add an
      admin with <code>bin/prod fix make-admin EMAIL</code>
      once they have logged in. See <code>docs/production.md</code>.
    </p>
    <.table id="admins" rows={@admins} row_id={&"admin-#{&1.id}"} class="table-striped">
      <:col :let={admin} label="Email">
        <.email id={"admin-#{admin.id}-email"} email={admin.email} />
      </:col>
      <:col :let={admin} label="Last team">
        <%= if team = @teams[admin.last_team_id] do %>
          <.a navigate={~p"/teams/#{team}"}>{team.name}</.a>
        <% end %>
      </:col>
      <:col :let={admin} label="Passkeys">{Map.get(@passkeys, admin.id, "None")}</:col>
    </.table>
    """
  end
end
