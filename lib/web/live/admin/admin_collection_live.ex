defmodule Web.Admin.AdminCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.AdminTabs

  alias App.Accounts
  alias App.Model.Team

  def mount(_params, _session, socket) do
    admins = Accounts.get_admins()
    teams = Map.new(Team.get_all(), &{&1.id, &1})

    socket =
      socket
      |> assign(page_title: "Admins", admins: admins, teams: teams, now: DateTime.utc_now())

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">Admin</h1>
    <.admin_tabs current={:admins} />
    <h2 class="heading">Admins</h2>
    <p class="max-w-prose">
      Admins can open every team, refresh any team from D4H, and set up organizations. An
      admin is added from a production console; see <code>docs/deployment.md</code>.
    </p>
    <.table id="admins" rows={@admins} row_id={&"admin-#{&1.id}"} class="table-striped">
      <:col :let={admin} label="Email">{admin.email}</:col>
      <:col :let={admin} label="Last team">
        <%= if team = @teams[admin.last_team_id] do %>
          <.a navigate={~p"/#{team.subdomain}"}>{team.name}</.a>
        <% end %>
      </:col>
      <:col :let={admin} label="Last seen" class="whitespace-nowrap">
        {last_seen(admin, @teams[admin.last_team_id], @now)}
      </:col>
    </.table>
    """
  end

  # In the zone of the team they last opened, since a user has no zone of their own.
  defp last_seen(%{last_seen_at: nil}, _team, _now), do: "Never"

  defp last_seen(admin, team, now) do
    timezone = if team, do: team.timezone, else: "Etc/UTC"
    Service.Format.days_ago(admin.last_seen_at, now, timezone)
  end
end
