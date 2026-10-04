defmodule Web.AdminDashboardLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamManagers

  alias App.Accounts.User
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

    assign(socket,
      managers: managers,
      grants: grants,
      logins: logins,
      login_emails: MapSet.new(users, &String.downcase(&1.email))
    )
  end

  def handle_info({:team_refreshed, updated_team}, socket) do
    teams =
      Enum.map(socket.assigns.teams, fn team ->
        if team.id == updated_team.id, do: updated_team, else: team
      end)

    {:noreply, assign(socket, teams: teams)}
  end

  def render(assigns) do
    ~H"""
    <div class="mb-p flex flex-wrap items-center justify-between gap-p">
      <h1 class="title mb-0">Admin</h1>
      <div class="flex items-center gap-p">
        <span id="refresh-summary" class="text-sm text-secondary-1">
          {refresh_summary(@teams)}
        </span>
        <.button type="button" variant={:warning} size={:sm} phx-click="refresh-all">
          Refresh All Teams
        </.button>
      </div>
    </div>
    <.table id="teams" rows={@teams} row_id={&"team-#{&1.id}"} class="table-striped">
      <:col :let={team} label="Team" class="md:w-56">
        <div class="flex items-start gap-2">
          <img
            id={"team-#{team.id}-logo"}
            src={~p"/teams/#{team.subdomain}/logo?shape=square"}
            width="32"
            height="32"
            class="size-8 shrink-0 rounded"
            alt=""
          />
          <div>
            <.a navigate={~p"/#{team.subdomain}"}>{team.name}</.a>
            <.hint>
              <span class="whitespace-nowrap">{team.subdomain} · ID {team.id}</span>
            </.hint>
          </div>
        </div>
      </:col>
      <:col :let={team} label="Last seen" class="whitespace-nowrap">
        <span id={"team-#{team.id}-last-seen"}>{team_last_seen(team, @logins[team.id], @now)}</span>
      </:col>
      <:col :let={team} label="Contacts">
        <span :if={@logins[team.id] == []} class="text-danger-1">No users</span>
        <ul :if={@logins[team.id] != []}>
          <li
            :for={user <- @logins[team.id]}
            class="flex items-baseline gap-2 md:whitespace-nowrap"
          >
            <span>{user.email}</span>
            <span
              :if={user.last_seen_at}
              class="ml-auto pl-p text-sm text-secondary-1"
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

    <section id="managers" class="mt-p2">
      <h2 class="heading">Team managers</h2>
      <p class="max-w-3xl text-sm text-secondary-1">
        Everyone D4H makes an Owner or Editor who isn't retired and hasn't left, from the last
        refresh, leaving out the team key's own account. Under #57 these people get access,
        and only these, plus any email an admin let in. Flagged: an email outside the team's
        usual domain, and anyone not operational.
      </p>
      <div :for={team <- @teams} id={"managers-#{team.id}"} class="mb-p2">
        <h3 class="font-bold">
          {team.name} · {length(@managers[team.id])} managers
        </h3>
        <.team_managers
          id={"managers-list-#{team.id}"}
          managers={@managers[team.id]}
          grants={@grants[team.id] || []}
          login_emails={@login_emails}
        />
      </div>
    </section>

    <dl id="key-notes" class="mt-p2 max-w-3xl text-sm">
      <dt>Last seen</dt>
      <dd>
        The last time someone on the team opened a team page. Admin visits don't count.
        Dates before mid-September 2026 are last logins, so the real last visit can be up
        to 60 days later.
      </dd>
      <dt>Team key</dt>
      <dd>
        The team's D4H key, saved in Team Settings, and the D4H member it belongs to. SAR Duty
        uses it for every D4H request. "Person's key" means the member isn't a SAR Duty
        account, so the key stops working if that person leaves.
      </dd>
    </dl>
    """
  end

  attr :result, :string

  defp refresh_status(assigns) do
    assigns = assign(assigns, :state, Team.refresh_state(assigns.result))

    ~H"""
    <span :if={@state == :never} class="text-secondary-1">Never refreshed</span>
    <span :if={@state == :ok} class="text-success-1">OK</span>
    <span :if={@state == :refreshing} class="text-sm text-primary-1">
      <span class="mr-1 inline-block h-3 w-3 animate-spin rounded-full border-2 border-current border-t-transparent"></span>
      {@result}
    </span>
    <span :if={@state == :failed} class="text-sm text-danger-1">
      {String.replace_prefix(@result, "Error: ", "")}
    </span>
    """
  end

  def handle_event("refresh-all", _params, socket) do
    %{}
    |> ScheduleTeamRefreshesWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "All team refreshes have been scheduled.")}
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

  defp key_summary(%Team{} = team) do
    if Team.key_owner_is_sar_duty?(team),
      do: "Team key: #{team.d4h_access_key_owner}",
      else: "Person's key: #{team.d4h_access_key_owner}"
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
