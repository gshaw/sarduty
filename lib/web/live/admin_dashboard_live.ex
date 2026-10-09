defmodule Web.AdminDashboardLive do
  use Web, :live_view_app_layout

  import Web.Components.AdminTabs

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.Team
  alias App.Model.TeamLoginGrant
  alias App.Worker.RefreshTeamDataWorker
  alias App.Worker.ScheduleTeamRefreshesWorker

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")

    teams = Team.get_all()
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(page_title: "Admin", teams: teams, now: now)
      |> assign_access(teams, now)

    {:ok, socket}
  end

  # Who reaches each team: its D4H managers, emails an admin let in, and which have logins.
  defp assign_access(socket, teams, now) do
    managers = Map.new(teams, &{&1.id, Member.get_managers(&1, now)})
    users = App.Repo.all(User)
    grants = Enum.group_by(TeamLoginGrant.get_all(), & &1.team_id)
    logins = Map.new(teams, &{&1.id, logins(users, managers[&1.id], grants[&1.id] || [])})

    assign(socket, managers: managers, logins: logins)
  end

  def handle_info({:team_refreshed, updated_team}, socket) do
    # The broadcast team has no organization loaded, so keep the one from mount.
    teams =
      Enum.map(socket.assigns.teams, fn team ->
        if team.id == updated_team.id,
          do: %{updated_team | organization: team.organization},
          else: team
      end)

    {:noreply, assign(socket, teams: teams)}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">Admin</h1>
    <.admin_tabs current={:teams} />
    <div class="heading-row">
      <h2 class="heading">Teams</h2>
      <div class="flex items-center gap-4">
        <span id="refresh-summary" class="hint">
          {refresh_summary(@teams)}
        </span>
        <.button type="button" variant={:warning} phx-click="refresh-all">
          Refresh all teams
        </.button>
      </div>
    </div>
    <.table id="teams" rows={@teams} row_id={&"team-#{&1.id}"} class="table-striped">
      <:col :let={team} label="Team">
        <div class="media items-start">
          <img
            id={"team-#{team.id}-logo"}
            src={~p"/teams/#{team}/logo?shape=square"}
            width="32"
            height="32"
            class="size-8 rounded"
            alt=""
          />
          <div>
            <.a navigate={~p"/teams/#{team}"}>{team.name}</.a>
            <.hint>
              <span class="whitespace-nowrap">{team.subdomain} · ID {team.id}</span>
              <span :if={team.organization} id={"team-#{team.id}-organization"} class="block">
                {team.organization.short_name}
              </span>
            </.hint>
          </div>
        </div>
      </:col>
      <:col :let={team} label="Last seen" class="whitespace-nowrap">
        <span id={"team-#{team.id}-last-seen"}>{team_last_seen(team, @logins[team.id], @now)}</span>
      </:col>
      <:col :let={team} label="Contacts">
        <.a id={"team-#{team.id}-managers"} navigate={~p"/teams/#{team}/settings/managers"}>
          {Service.Format.count(length(@managers[team.id]),
            one: "%d team admin",
            many: "%d team admins"
          )}
        </.a>
        <span :if={@logins[team.id] == []} class="block text-danger-text">No accounts</span>
        <ul :if={@logins[team.id] != []}>
          <li
            :for={user <- @logins[team.id]}
            class="flex items-baseline gap-2 md:whitespace-nowrap"
          >
            <span>{user.email}</span>
            <span
              :if={user.last_seen_at}
              class="hint ml-auto pl-4"
              title={Service.Format.datetime_short(user.last_seen_at, team.timezone)}
            >
              {Service.Format.days_ago(user.last_seen_at, @now, team.timezone)}
            </span>
          </li>
        </ul>
      </:col>
      <:col :let={team} label="D4H refresh">
        <.refresh_status result={team.d4h_refresh_result} />
        <.hint>
          <div id={"team-#{team.id}-key"}>{key_summary(team)}</div>
          <div :if={team.d4h_access_key_saved_at} class="whitespace-nowrap">
            Key saved {Service.Format.date_long(team.d4h_access_key_saved_at, team.timezone)}
          </div>
          <div :if={team.d4h_refreshed_at} class="whitespace-nowrap">
            Last OK {format_refreshed_at(team)}
          </div>
          <div :if={team.d4h_synced_at} id={"team-#{team.id}-synced"} class="whitespace-nowrap">
            Synced {Service.Format.minutes_ago(team.d4h_synced_at, DateTime.utc_now(), team.timezone)}
          </div>
        </.hint>
        <.button
          type="button"
          size={:sm}
          phx-click="refresh"
          phx-value-team-id={team.id}
          disabled={Team.refresh_state(team.d4h_refresh_result) == :refreshing}
        >
          Refresh
        </.button>
      </:col>
    </.table>

    <dl id="key-notes" class="mt-8 max-w-3xl text-sm">
      <dt>Last seen</dt>
      <dd>
        The last time someone on the team opened a team page. Admin visits do not count.
        Dates before mid-September 2026 are last logins, so the real last visit can be up
        to 60 days later.
      </dd>
      <dt>Team key</dt>
      <dd>
        The team's D4H access key, saved in Team settings, and the D4H member it belongs to. SAR Duty
        uses it for every D4H request. "Person's key" means the member is not a SAR Duty
        account, so the key stops working if that person leaves.
      </dd>
    </dl>
    """
  end

  attr :result, :string

  defp refresh_status(assigns) do
    assigns = assign(assigns, :state, Team.refresh_state(assigns.result))

    ~H"""
    <span :if={@state == :never} class="text-text-muted">Never refreshed</span>
    <span :if={@state == :ok} class="text-success-text">OK</span>
    <.spinner :if={@state == :refreshing} class="text-sm text-link">{@result}</.spinner>
    <span :if={@state == :failed} class="text-sm text-danger-text">
      {String.replace_prefix(@result, "Error: ", "")}
    </span>
    """
  end

  def handle_event("refresh-all", _params, socket) do
    %{}
    |> ScheduleTeamRefreshesWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Refreshes scheduled for all teams.")}
  end

  def handle_event("refresh", %{"team-id" => team_id}, socket) do
    %{team_id: String.to_integer(team_id)}
    |> RefreshTeamDataWorker.new()
    |> Oban.insert()

    {:noreply, socket}
  end

  defp refresh_summary(teams) do
    ok_count = Enum.count(teams, &(Team.refresh_state(&1.d4h_refresh_result) == :ok))
    "#{ok_count} of #{length(teams)} teams refreshed OK."
  end

  # Users who can reach the team, by email: its managers who have logged in, and emails
  # an admin let in.
  defp logins(users, managers, grants) do
    emails =
      managers
      |> MapSet.new(&String.downcase(&1.email || ""))
      |> MapSet.union(MapSet.new(grants, & &1.email))

    users
    |> Enum.filter(&MapSet.member?(emails, String.downcase(&1.email)))
    |> Enum.sort_by(& &1.email)
  end

  defp key_summary(%Team{d4h_access_key: key}) when key in [nil, ""], do: "No team key"
  defp key_summary(%Team{d4h_access_key_owner: nil}), do: "Team key"

  # Records names the key itself, so whose it is says nothing there.
  defp key_summary(%Team{} = team) do
    cond do
      D4H.records?(team) -> "SAR Duty Records key: #{team.d4h_access_key_owner}"
      Team.key_owner_is_sar_duty?(team) -> "Team key: #{team.d4h_access_key_owner}"
      true -> "Person's key: #{team.d4h_access_key_owner}"
    end
  end

  # The most recent visit by anyone on the team.
  defp team_last_seen(team, logins, now) do
    logins
    |> Enum.map(& &1.last_seen_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
    |> Service.Format.days_ago(now, team.timezone)
  end

  defp format_refreshed_at(team) do
    if team.d4h_refreshed_at do
      Service.Format.datetime_short(team.d4h_refreshed_at, team.timezone)
    end
  end
end
