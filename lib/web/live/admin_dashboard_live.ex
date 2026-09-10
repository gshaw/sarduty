defmodule Web.AdminDashboardLive do
  use Web, :live_view_app_layout

  alias App.Model.Team
  alias App.Operation.RefreshD4HData.ResolveAccessKey
  alias App.Worker.RefreshTeamDataWorker
  alias App.Worker.ScheduleTeamRefreshesWorker

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")

    teams = Team.get_all_with_users()

    socket =
      socket
      |> assign(page_title: "Admin")
      |> assign(teams: teams)

    {:ok, socket}
  end

  def handle_info({:team_refreshed, updated_team}, socket) do
    # The broadcast team has no users loaded, so keep the ones from mount.
    teams =
      Enum.map(socket.assigns.teams, fn team ->
        if team.id == updated_team.id, do: %{updated_team | users: team.users}, else: team
      end)

    {:noreply, assign(socket, teams: teams)}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title mb-p">Admin</h1>
    <div class="mb-p flex flex-wrap items-center gap-4">
      <.button type="button" variant={:warning} phx-click="refresh-all">
        Refresh All Teams
      </.button>
      <span id="refresh-summary">{refresh_summary(@teams)}</span>
    </div>
    <.table id="teams" rows={@teams} row_id={&"team-#{&1.id}"}>
      <:col :let={team} label="Team">
        <.a navigate={~p"/#{team.subdomain}"}>{team.name}</.a>
        <.hint>
          <span class="whitespace-nowrap">{team.subdomain} · ID {team.id}</span>
        </.hint>
      </:col>
      <:col :let={team} label="Contacts">
        <span :if={team.users == []} class="text-danger-1">No users</span>
        <ul :if={team.users != []} class="list-disc pl-4">
          <li :for={user <- team.users}>
            {user.email}
            <.badge :if={key_badge(team, user) == :refresh} kind={:primary}>Refresh key</.badge>
            <.badge :if={key_badge(team, user) == :personal}>D4H key</.badge>
          </li>
        </ul>
      </:col>
      <:col :let={team} label="Team key" class="whitespace-nowrap">
        {if ResolveAccessKey.key?(team.d4h_access_key), do: "Yes", else: "No"}
      </:col>
      <:col :let={team} label="Last OK refresh" class="whitespace-nowrap">
        {format_refreshed_at(team)}
      </:col>
      <:col :let={team} label="Status">
        <.refresh_status result={team.d4h_refresh_result} />
      </:col>
      <:col :let={team} label="">
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

    <dl id="key-notes" class="mt-p">
      <dt>Team key</dt>
      <dd>
        The team's own D4H key, saved in Team Settings. The refresh uses it when there is one.
      </dd>
      <dt>
        <.badge kind={:primary}>Refresh key</.badge>
      </dt>
      <dd>
        The team has no key of its own, so the refresh borrows this person's personal D4H key.
      </dd>
      <dt>
        <.badge>D4H key</.badge>
      </dt>
      <dd>
        This person saved a personal D4H key in Settings. Pages that call D4H live, like
        activity attendance and the mileage report, use it while they are signed in.
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
    <div :if={@state == :refreshing} class="flex items-center gap-2 text-primary-1">
      <span class="inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"></span>
      <span>{@result}</span>
    </div>
    <span :if={@state == :failed} class="text-danger-1">
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

  # :refresh for the member whose personal key the refresh borrows, :personal for any
  # other member with a key.
  defp key_badge(team, user) do
    cond do
      ResolveAccessKey.key_owner(team, team.users) == user -> :refresh
      ResolveAccessKey.key?(user.d4h_access_key) -> :personal
      true -> nil
    end
  end

  defp format_refreshed_at(team) do
    if team.d4h_refreshed_at do
      Service.Format.datetime_short(team.d4h_refreshed_at, team.timezone)
    end
  end
end
