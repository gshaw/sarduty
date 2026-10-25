defmodule Web.Org.TeamLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.TeamRefresh

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Team
  alias App.Operation.SetTeamOrganization
  alias App.Operation.SyncD4HChanges
  alias App.Repo
  alias App.ViewData.TeamDashboardViewData
  alias App.ViewData.TeamSummary

  # One team in an organization (#512): its totals, never its people. Found through the
  # organization, so a team that isn't in it is a 404. SAR Duty admins also remove it.
  def mount(%{"subdomain" => subdomain}, _session, socket) do
    organization = socket.assigns.current_organization

    team =
      Team
      |> where([t], t.organization_id == ^organization.id and t.subdomain == ^subdomain)
      |> Repo.one()

    if is_nil(team), do: raise(Web.Status.NotFound)

    {:ok, socket |> assign(page_title: team.name) |> assign_team(team)}
  end

  defp assign_team(socket, team) do
    organization = socket.assigns.current_organization
    team = %{team | organization: organization}
    now = DateTime.utc_now()
    year = Service.YearRange.year_in(now, organization.timezone)

    assign(socket,
      team: team,
      now: now,
      members: [team] |> TeamSummary.member_counts(now) |> Map.get(team.id, 0),
      last_seen: TeamSummary.last_seen([team], now)[team.id],
      hours_tags: hours_tags(team),
      untagged: TeamDashboardViewData.untagged_rows(team, now),
      letters: for(y <- [year, year - 1], do: {y, letter_count(team, y)})
    )
  end

  defp letter_count(team, year),
    do: [team] |> TeamSummary.letter_counts(year) |> Map.get(team.id, 0)

  # Each kind's tag, and whether the team names it itself rather than the organization.
  defp hours_tags(team) do
    merged = Activity.hours_tags(team)
    own = Activity.organization_hours_tags(team.organization)

    for kind <- [:primary, :secondary, :other], merged[kind] do
      %{kind: kind, tag: merged[kind], own?: is_nil(own[kind])}
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Teams" path={~p"/orgs/#{@current_organization}"} />
      <:item label={@team.name} />
    </.breadcrumbs>
    <div class="media mb-6">
      <img
        src={~p"/teams/#{@team}/logo?shape=square"}
        width="48"
        height="48"
        class="size-12 rounded"
        alt=""
      />
      <h1 class="title mb-0">{@team.name}</h1>
    </div>

    <.banner
      :if={not_refreshing?(@team)}
      id="team-refresh-banner"
      kind={:warning}
      title={not_refreshed_since(@team)}
      class="mb-6"
    >
      <p :if={SyncD4HChanges.key_rejected?(@team)} class="mb-0">
        Its access key was refused. A team admin saves a new one in team settings.
      </p>
      <p :if={!SyncD4HChanges.key_rejected?(@team)} class="mb-0">
        SAR Duty could not refresh the team's records. It tries again every night.
      </p>
    </.banner>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl id="team-facts">
          <dt>Refreshes from</dt>
          <dd>{D4H.service_name(@team)}</dd>
          <dt>Members</dt>
          <dd id="team-members">
            {Service.Format.count(@members, one: "%d member", many: "%d members")}
          </dd>
          <dt>Last seen</dt>
          <dd id="team-last-seen">
            {Service.Format.days_ago(@last_seen, @now, @team.timezone) || "Never"}
          </dd>
          <dt>Hours tags</dt>
          <dd id="team-hours-tags">
            <div :for={row <- @hours_tags}>
              {row.tag} <span class="hint">{row.kind}{if row.own?, do: ", the team's own"}</span>
            </div>
          </dd>
          <dt>Untagged activities</dt>
          <dd id="team-untagged">
            <div :if={Enum.all?(@untagged, &(&1.count == 0))}>None</div>
            <div :for={row <- @untagged} :if={row.count > 0}>{row.year}: {row.count}</div>
          </dd>
          <dt>Tax credit letters</dt>
          <dd id="team-letters">
            <div :for={{year, count} <- @letters}>
              {year}: {if count == 0, do: "None", else: count}
            </div>
          </dd>
        </dl>
      </aside>
      <main class="content-2/3">
        <section :if={@current_user.is_admin} id="team-remove" class="measure">
          <h2 class="heading">Remove from {@current_organization.short_name}</h2>
          <p>
            Its ID cards stop naming {@current_organization.name}, and its tax credit letters go
            back to its own hours tags. Its ID cards stay on or off. Its team admins get an
            email.
          </p>
          <.button
            id="remove-team"
            type="button"
            variant={:danger}
            phx-click="remove"
            data-confirm={"Remove #{@team.name} from #{@current_organization.short_name}? Its team admins get an email."}
          >
            Remove {@team.name}
          </.button>
        </section>
      </main>
    </div>
    """
  end

  def handle_event("remove", _params, socket) do
    %{team: team, current_organization: organization, current_user: user} = socket.assigns

    case SetTeamOrganization.call(team, nil, user) do
      {:ok, team} ->
        socket =
          socket
          |> put_flash(:info, "Removed #{team.name} from #{organization.short_name}.")
          |> push_navigate(to: ~p"/orgs/#{organization}")

        {:noreply, socket}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Only a SAR Duty admin removes a team.")}

      {:error, :not_in_organization} ->
        {:noreply, push_navigate(socket, to: ~p"/orgs/#{organization}")}
    end
  end
end
