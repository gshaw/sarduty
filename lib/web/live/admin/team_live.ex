defmodule Web.Admin.TeamLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamRefresh

  alias App.Adapter.D4H
  alias App.Model.MCPToken
  alias App.Model.Team
  alias App.Model.TeamLoginGrant
  alias App.Operation.SetTeamIdCards
  alias App.Operation.SetTeamMCP
  alias App.Repo
  alias App.ViewData.TeamSummary
  alias App.Worker.RefreshTeamDataWorker

  # One team's SAR Duty admin page (#513): its refresh, who reaches it as a team admin,
  # and its ID cards and MCP switches.
  def mount(%{"id" => id}, _session, socket) do
    team =
      with {id, ""} <- Integer.parse(id), %Team{} = team <- Team.get(id) do
        Repo.preload(team, :organization)
      else
        _none -> raise Web.Status.NotFound
      end

    if connected?(socket), do: Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")

    {:ok, socket |> assign(page_title: team.name) |> assign_team(team)}
  end

  defp assign_team(socket, team) do
    now = DateTime.utc_now()

    socket
    |> assign(
      team: team,
      now: now,
      team_admins: TeamSummary.team_admin_rows(team, now),
      cards: Map.get(TeamSummary.card_counts(), team.id, 0),
      tokens: Map.get(MCPToken.count_live_by_team(), team.id, 0)
    )
    |> assign_new(:grant_form, fn ->
      grant_form(TeamLoginGrant.build_changeset(%TeamLoginGrant{}))
    end)
  end

  defp grant_form(changeset), do: to_form(changeset, as: "grant")

  def handle_info(
        {:team_refreshed, %Team{id: id} = updated},
        %{assigns: %{team: %{id: id}}} = socket
      ),
      do:
        {:noreply,
         assign(socket, team: %{updated | organization: socket.assigns.team.organization})}

  # Other teams' refreshes, and anything else.
  def handle_info(_message, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Teams" path={~p"/admin"} />
      <:item label={@team.name} />
    </.breadcrumbs>
    <.heading_row>
      <div class="media">
        <img
          src={~p"/teams/#{@team}/logo?shape=square"}
          width="48"
          height="48"
          class="size-12 rounded"
          alt=""
        />
        <h1 class="title mb-0">{@team.name}</h1>
      </div>
      <:action>
        <.button id="open-team" navigate={~p"/teams/#{@team}"}>Open team</.button>
      </:action>
    </.heading_row>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl id="team-facts">
          <dt>Subdomain</dt>
          <dd>{@team.subdomain}</dd>
          <dt>ID</dt>
          <dd>{@team.id}</dd>
          <dt>Refreshes from</dt>
          <dd>
            {D4H.service_name(@team)}
            <.hint :if={region(@team)}>{region(@team)}</.hint>
          </dd>
          <dt>Organization</dt>
          <dd id="team-organization">
            <.a
              :if={@team.organization}
              navigate={~p"/orgs/#{@team.organization}/teams/#{@team}"}
            >{@team.organization.name}</.a>
            <span :if={!@team.organization}>None</span>
          </dd>
          <dt>Time zone</dt>
          <dd>{@team.timezone}</dd>
          <dt>Signed up</dt>
          <dd>{Service.Format.date_long(@team.inserted_at, @team.timezone)}</dd>
          <dt>Member logins</dt>
          <dd>{on_off(@team.member_logins)}</dd>
          <dt>Chores</dt>
          <dd>{on_off(Team.chores?(@team))}</dd>
          <dt>Actions</dt>
          <dd>
            <ul class="action-list">
              <li><.a navigate={~p"/admin/events?team=#{@team.id}"}>Events for this team</.a></li>
            </ul>
          </dd>
        </dl>
      </aside>
      <main class="content-2/3">
        <section id="team-refresh" class="mb-8">
          <h2 class="heading">Refresh</h2>
          <dl>
            <dt>Last refresh</dt>
            <dd id="team-refresh-result">
              <.refresh_result team={@team} />
              <.hint :if={@team.d4h_refreshed_at}>
                Last OK {Service.Format.datetime_short(@team.d4h_refreshed_at, @team.timezone)}
              </.hint>
            </dd>
            <dt>Synced</dt>
            <dd id="team-synced">
              {if @team.d4h_synced_at,
                do: Service.Format.minutes_ago(@team.d4h_synced_at, @now, @team.timezone),
                else: "Never"}
            </dd>
            <dt>Key</dt>
            <dd>
              <.team_key team={@team} id="team-key" />
              <.hint :if={@team.d4h_access_key_saved_at}>
                Saved {Service.Format.date_long(@team.d4h_access_key_saved_at, @team.timezone)}
              </.hint>
            </dd>
          </dl>
          <.warning_text :if={match?({:person, _name}, key_kind(@team))} id="person-key" class="mb-4">
            This key is a person's, so it stops working if they leave the team. Ask a team admin
            to save one from an account set up for SAR Duty.
          </.warning_text>
          <.button
            id="refresh-team"
            type="button"
            phx-click="refresh"
            disabled={Team.refresh_state(@team.d4h_refresh_result) == :refreshing}
          >
            Refresh from {D4H.service_name(@team)}
          </.button>
        </section>

        <section id="team-admins-section" class="mb-8">
          <h2 class="heading">Team admins</h2>
          <p class="max-w-3xl">
            Everyone who reaches the team as a team admin. Members who log in, and SAR Duty
            admins, are not listed.
          </p>
          <p :if={@team_admins == []} id="no-team-admins" class="text-danger-text">None</p>
          <.table
            :if={@team_admins != []}
            id="team-admins"
            rows={@team_admins}
            row_id={&"team-admin-#{&1.email}"}
            class="table-striped"
          >
            <:col :let={row} label="Email"><span class="break-all">{row.email}</span></:col>
            <:col :let={row} label="Why" class="max-md:hidden">
              <div :for={role <- row.roles}>{role}</div>
              <div :if={row.grant}>
                Login grant{if row.grant.reason, do: ": #{row.grant.reason}"}
                <.hint :if={row.grant.added_by_user}>Added by {row.grant.added_by_user.email}</.hint>
              </div>
            </:col>
            <:col :let={row} label="Last seen" class="whitespace-nowrap max-md:hidden">
              {Service.Format.days_ago(row.last_seen_at, @now, @team.timezone) || "Never"}
            </:col>
            <:col :let={row} label="" class="w-px">
              <.button
                :if={row.grant}
                id={"remove-grant-#{row.grant.id}"}
                type="button"
                size={:sm}
                variant={:danger}
                phx-click="remove_grant"
                phx-value-id={row.grant.id}
                data-confirm={remove_grant_confirm(row, @team)}
              >
                Remove
              </.button>
            </:col>
          </.table>

          <.form
            for={@grant_form}
            id="grant-form"
            phx-change="validate_grant"
            phx-submit="add_grant"
            class="mt-6"
          >
            <h3 class="subheading">Add a login grant</h3>
            <p class="hint mb-4">
              A grant can do everything a team admin does, including sending changes to {D4H.service_name(
                @team
              )}. Add one for someone {D4H.service_name(@team)} cannot make an Owner or Editor, such as a shared office address.
            </p>
            <div class="grid md:grid-cols-2 gap-x-6">
              <.input field={@grant_form[:email]} type="email" label="Email" />
              <.input field={@grant_form[:reason]} label="Why (optional)" placeholder="Treasurer" />
            </div>
            <.form_actions>
              <.button variant={:success}>Add login grant</.button>
            </.form_actions>
          </.form>
        </section>

        <section id="team-id-cards" class="mb-8 max-w-3xl">
          <h2 class="heading">ID cards</h2>
          <p id="team-id-cards-state">
            <span :if={@team.id_cards_enabled} class="text-success-text">On</span>
            <span :if={!@team.id_cards_enabled} class="text-text-muted">Off</span>
            · {Service.Format.count(@cards, one: "%d card", many: "%d cards")}
          </p>
          <p>
            Check a team is real before turning them on: anyone can verify a card on {Web.VerifyHost.host()}, and anyone can sign up a team. Turning them off cancels every card.
          </p>
          <p :if={@team.organization} id="team-id-cards-organization">
            Its
            <.a navigate={~p"/orgs/#{@team.organization}/settings/admins"}>organization admins</.a>
            can turn them on or off too.
          </p>
          <.button
            :if={!@team.id_cards_enabled}
            id="id-cards-on"
            type="button"
            phx-click="id_cards"
            phx-value-enabled="true"
          >
            Turn on ID cards
          </.button>
          <.button
            :if={@team.id_cards_enabled}
            id="id-cards-off"
            type="button"
            variant={:danger}
            phx-click="id_cards"
            phx-value-enabled="false"
            data-confirm={"Turn off ID cards for #{@team.name}? This cancels its #{Service.Format.count(@cards, one: "%d card", many: "%d cards")}, and its team admins get an email."}
          >
            Turn off ID cards
          </.button>
        </section>

        <section id="team-mcp" class="max-w-3xl">
          <h2 class="heading">MCP</h2>
          <p id="team-mcp-state">
            <span :if={@team.mcp_enabled} class="text-success-text">On</span>
            <span :if={!@team.mcp_enabled} class="text-text-muted">Off</span>
            · {Service.Format.count(@tokens, one: "%d token", many: "%d tokens")}
          </p>
          <p>
            Team admins create MCP tokens once it is on. Turning it off revokes every token on
            the team. See <code>docs/mcp.md</code>.
          </p>
          <.button
            :if={!@team.mcp_enabled}
            id="mcp-on"
            type="button"
            phx-click="mcp"
            phx-value-enabled="true"
          >
            Turn on MCP
          </.button>
          <.button
            :if={@team.mcp_enabled}
            id="mcp-off"
            type="button"
            variant={:danger}
            phx-click="mcp"
            phx-value-enabled="false"
            data-confirm={"Turn off MCP for #{@team.name}? This revokes its #{Service.Format.count(@tokens, one: "%d token", many: "%d tokens")}."}
          >
            Turn off MCP
          </.button>
        </section>
      </main>
    </div>
    """
  end

  attr :team, :map, required: true

  defp refresh_result(assigns) do
    assigns = assign(assigns, :state, Team.refresh_state(assigns.team.d4h_refresh_result))

    ~H"""
    <span :if={@state == :never} class="text-danger-text">Never refreshed</span>
    <span :if={@state == :ok} class="text-success-text">OK</span>
    <.spinner :if={@state == :refreshing} class="text-sm text-link">
      {@team.d4h_refresh_result}
    </.spinner>
    <span :if={@state == :failed} class="text-danger-text">
      {String.replace_prefix(@team.d4h_refresh_result, "Error: ", "")}
    </span>
    """
  end

  defp on_off(true), do: "On"
  defp on_off(_off), do: "Off"

  defp region(team) do
    Enum.find_value(D4H.regions(), fn {name, host} -> host == team.d4h_api_host && name end)
  end

  # An email that is a D4H Owner too keeps that; Remove takes away only the grant.
  defp remove_grant_confirm(%{roles: [], email: email}, team),
    do: "Remove #{email}'s login grant? They can no longer open #{team.name}."

  defp remove_grant_confirm(%{email: email}, _team),
    do: "Remove #{email}'s login grant? Their own access still lets them in."

  def handle_event("validate_grant", %{"grant" => params}, socket) do
    changeset =
      %TeamLoginGrant{team_id: socket.assigns.team.id}
      |> TeamLoginGrant.build_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, grant_form: grant_form(changeset))}
  end

  def handle_event("add_grant", %{"grant" => params}, socket) do
    %{team: team, current_user: user} = socket.assigns

    case TeamLoginGrant.add(team, params, user) do
      {:ok, grant} ->
        socket =
          socket
          |> assign(grant_form: grant_form(TeamLoginGrant.build_changeset(%TeamLoginGrant{})))
          |> assign_team(team)
          |> put_flash(:info, "Added a login grant for #{grant.email}.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, grant_form: grant_form(changeset))}
    end
  end

  def handle_event("remove_grant", %{"id" => id}, socket) do
    %{team: team, current_user: user} = socket.assigns

    socket =
      case TeamLoginGrant.remove(team, id, user) do
        {:ok, grant} -> put_flash(socket, :info, "Removed #{grant.email}'s login grant.")
        {:error, :not_found} -> put_flash(socket, :error, "That login grant was removed already.")
      end

    {:noreply, assign_team(socket, team)}
  end

  def handle_event("refresh", _params, socket) do
    RefreshTeamDataWorker.enqueue(socket.assigns.team)
    {:noreply, socket}
  end

  def handle_event("id_cards", %{"enabled" => enabled}, socket) do
    %{team: team, current_user: user} = socket.assigns
    {:ok, team} = SetTeamIdCards.call(team, enabled == "true", user)

    message =
      if team.id_cards_enabled,
        do: "ID cards turned on for #{team.name}.",
        else: "ID cards turned off for #{team.name}. Its cards are cancelled."

    {:noreply,
     socket |> assign_team(Repo.preload(team, :organization)) |> put_flash(:info, message)}
  end

  def handle_event("mcp", %{"enabled" => enabled}, socket) do
    %{team: team, current_user: user} = socket.assigns
    {:ok, team} = SetTeamMCP.call(team, enabled == "true", user)

    message =
      if team.mcp_enabled,
        do: "MCP turned on for #{team.name}.",
        else: "MCP turned off for #{team.name}. Its tokens are revoked."

    {:noreply,
     socket |> assign_team(Repo.preload(team, :organization)) |> put_flash(:info, message)}
  end
end
