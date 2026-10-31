defmodule Web.AdminDashboardLive do
  use Web, :live_view_app_layout

  import Web.Components.StatSwitch
  import Web.Components.TeamRefresh

  alias App.Model.Team
  alias App.ViewData.TeamSummary
  alias App.ViewModel.TeamListViewModel
  alias App.Worker.ScheduleTeamRefreshesWorker

  @views ["all", "not-refreshing", "no-team-admins", "person-key", "id-cards-on", "mcp-on"]

  # Every team, one short row each (#513). Its emails, key, and switches are on its own
  # page, /admin/teams/:id. Refreshes update the rows live.
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")

    teams = Team.get_all() |> Enum.sort_by(&String.downcase(&1.name))
    now = DateTime.utc_now()
    emails = TeamSummary.team_admin_emails(teams, now)

    socket =
      assign(socket,
        page_title: "Teams",
        teams: teams,
        now: now,
        team_admins: Map.new(emails, fn {id, list} -> {id, length(list)} end),
        last_seen: TeamSummary.last_seen_from(emails),
        cards: TeamSummary.card_counts()
      )

    {:ok, socket}
  end

  def handle_params(params, _uri, socket),
    do:
      {:noreply, socket |> assign(view: TeamListViewModel.view(params, @views)) |> assign_rows()}

  defp assign_rows(socket) do
    %{teams: teams, view: view} = socket.assigns

    assign(socket,
      rows: Enum.filter(teams, &in_view?(&1, view, socket.assigns)),
      counts:
        Map.new(@views, fn v -> {v, Enum.count(teams, &in_view?(&1, v, socket.assigns))} end)
    )
  end

  # Each view's teams. The stat switch counts the same rows the table shows.
  defp in_view?(_team, "all", _assigns), do: true
  defp in_view?(team, "not-refreshing", _assigns), do: not_refreshing?(team)

  defp in_view?(team, "no-team-admins", assigns),
    do: Map.get(assigns.team_admins, team.id, 0) == 0

  defp in_view?(team, "person-key", _assigns), do: match?({:person, _name}, key_kind(team))
  defp in_view?(team, "id-cards-on", _assigns), do: team.id_cards_enabled
  defp in_view?(team, "mcp-on", _assigns), do: team.mcp_enabled

  @doc "The views, for the stat switch: its value and label."
  def views,
    do: [
      {"all", "All"},
      {"not-refreshing", "Not refreshing"},
      {"no-team-admins", "No team admins"},
      {"person-key", "Person's key"},
      {"id-cards-on", "ID cards on"},
      {"mcp-on", "MCP on"}
    ]

  defp view_path(view), do: ~p"/admin?#{TeamListViewModel.query_params(view, @views)}"

  def handle_info({:team_refreshed, updated_team}, socket) do
    # The broadcast team has no organization loaded, so keep the one from mount.
    teams =
      Enum.map(socket.assigns.teams, fn team ->
        if team.id == updated_team.id,
          do: %{updated_team | organization: team.organization},
          else: team
      end)

    {:noreply, socket |> assign(teams: teams) |> assign_rows()}
  end

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">Teams</h1>
      <:note><span id="refresh-summary">{refresh_summary(@teams)}</span></:note>
      <:action>
        <.button type="button" variant={:warning} phx-click="refresh-all">
          Refresh all teams
        </.button>
      </:action>
    </.heading_row>

    <.stat_switch id="team-views" label="Teams">
      <:view
        :for={{view, label} <- views()}
        id={"team-view-#{view}"}
        patch={view_path(view)}
        current={@view == view}
        count={@counts[view]}
      >
        {label}
      </:view>
    </.stat_switch>

    <.table id="teams" rows={@rows} row_id={&"team-#{&1.id}"} class="table-striped">
      <:col :let={team} label="Team">
        <div class="media">
          <img
            id={"team-#{team.id}-logo"}
            src={~p"/teams/#{team}/logo?shape=square"}
            width="32"
            height="32"
            class="size-8 rounded"
            alt=""
          />
          <div>
            <.a id={"team-#{team.id}-name"} navigate={~p"/admin/teams/#{team.id}"}>{team.name}</.a>
            <.hint>
              {team.subdomain}<span :if={team.organization} id={"team-#{team.id}-organization"}> · {team.organization.short_name}</span>
            </.hint>
          </div>
        </div>
      </:col>
      <:col :let={team} label="Last seen" class="whitespace-nowrap">
        <span id={"team-#{team.id}-last-seen"}>
          {Service.Format.days_ago(@last_seen[team.id], @now, team.timezone) || "Never"}
        </span>
      </:col>
      <:col :let={team} label="Team admins" class="max-md:hidden">
        <span
          id={"team-#{team.id}-team-admins"}
          class={Map.get(@team_admins, team.id, 0) == 0 && "text-danger-text"}
        >
          {if Map.get(@team_admins, team.id, 0) == 0, do: "None", else: @team_admins[team.id]}
        </span>
      </:col>
      <:col :let={team} label="Refresh">
        <.spinner
          :if={Team.refresh_state(team.d4h_refresh_result) == :refreshing}
          class="text-sm text-link"
        >
          Refreshing
        </.spinner>
        <.team_refresh
          :if={Team.refresh_state(team.d4h_refresh_result) != :refreshing}
          team={team}
          id={"team-#{team.id}-refresh"}
        />
      </:col>
      <:col :let={team} label="Key" class="max-md:hidden">
        <.team_key team={team} id={"team-#{team.id}-key"} />
      </:col>
      <:col :let={team} label="ID cards" class="max-md:hidden">
        <span id={"team-#{team.id}-cards"}>
          {if team.id_cards_enabled, do: Map.get(@cards, team.id, 0), else: "Off"}
        </span>
      </:col>
    </.table>

    <dl id="key-notes" class="mt-8 max-w-3xl text-sm">
      <dt>Last seen</dt>
      <dd>
        The last time a team admin opened one of the team's pages. Members' and SAR Duty site admins'
        visits do not count. Dates before mid-September 2026 are last logins, so the real last
        visit can be up to 60 days later.
      </dd>
      <dt>Team admins</dt>
      <dd>
        Who can log in as one: the D4H Owners and Editors with an email, and login grants. Last
        seen says who does.
      </dd>
      <dt>Key</dt>
      <dd>
        The team's access key, saved in team settings, and whose account it is. "Person's" means
        it stops working if that person leaves.
      </dd>
    </dl>
    """
  end

  def handle_event("refresh-all", _params, socket) do
    ScheduleTeamRefreshesWorker.enqueue()

    {:noreply, put_flash(socket, :info, "Refreshes scheduled for all teams.")}
  end

  defp refresh_summary(teams) do
    ok_count = Enum.count(teams, &(Team.refresh_state(&1.d4h_refresh_result) == :ok))
    "#{ok_count} of #{length(teams)} teams refreshed OK."
  end
end
