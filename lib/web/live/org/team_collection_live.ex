defmodule Web.Org.TeamCollectionLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.TeamRefresh

  alias App.Adapter.D4H
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Repo
  alias App.ViewData.TeamSummary

  # An organization's first page (#512): one row per team, with counts and never its
  # people. Teams are found through the organization only.
  def mount(_params, _session, socket) do
    organization = socket.assigns.current_organization
    now = DateTime.utc_now()

    teams =
      Team
      |> where([t], t.organization_id == ^organization.id)
      |> order_by([t], asc: t.name)
      |> preload(:organization)
      |> Repo.all()

    letter_year = TaxCreditLetter.current_year(now, organization.timezone)

    socket =
      assign(socket,
        page_title: "Teams",
        teams: teams,
        now: now,
        letter_year: letter_year,
        members: TeamSummary.member_counts(teams, now),
        last_seen: TeamSummary.last_seen(teams, now),
        cards: TeamSummary.card_counts(),
        untagged: TeamSummary.untagged_counts(teams, now),
        letters: TeamSummary.letter_counts(teams, letter_year)
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">Teams</h1>
    </.heading_row>

    <.empty_state :if={@teams == []} id="no-teams" title="No teams yet">
      A SAR Duty admin adds {@current_organization.short_name}'s teams.
    </.empty_state>

    <.table
      :if={@teams != []}
      id="teams"
      rows={@teams}
      row_id={&"team-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={team} label="Team">
        <div class="media">
          <img
            src={~p"/teams/#{team}/logo?shape=square"}
            width="32"
            height="32"
            class="size-8 rounded"
            alt=""
          />
          <div>
            <span id={"team-#{team.id}-name"}>{team.name}</span>
            <.hint>{D4H.service_name(team)}</.hint>
          </div>
        </div>
      </:col>
      <:col :let={team} label="Members" class="max-md:hidden">
        <span id={"team-#{team.id}-members"}>{Map.get(@members, team.id, 0)}</span>
      </:col>
      <:col :let={team} label="Last seen" class="whitespace-nowrap">
        <span id={"team-#{team.id}-last-seen"}>
          {Service.Format.days_ago(@last_seen[team.id], @now, team.timezone) || "Never"}
        </span>
      </:col>
      <:col :let={team} label="Refresh">
        <.team_refresh team={team} id={"team-#{team.id}-refresh"} />
      </:col>
      <:col :let={team} label="ID cards" class="max-md:hidden">
        <span id={"team-#{team.id}-cards"}>
          {if team.id_cards_enabled, do: Map.get(@cards, team.id, 0), else: "Off"}
        </span>
      </:col>
      <:col :let={team} label="Untagged activities" class="max-md:hidden">
        <span id={"team-#{team.id}-untagged"}>{count_or_none(@untagged[team.id])}</span>
      </:col>
      <:col :let={team} label={"Tax credit letters, #{@letter_year}"} class="max-md:hidden">
        <span id={"team-#{team.id}-letters"}>{count_or_none(@letters[team.id])}</span>
      </:col>
    </.table>

    <dl :if={@teams != []} id="team-notes" class="mt-8 max-w-3xl text-sm">
      <dt>Last seen</dt>
      <dd>The last time a team admin opened one of the team's pages.</dd>
      <dt>Refresh</dt>
      <dd>
        SAR Duty copies each team's records every 10 minutes and again each night. "Not
        refreshed since" gives the last time that worked.
      </dd>
      <dt>Untagged activities</dt>
      <dd>
        Published activities this year with no hours tag, and last year's too from January to
        April. Their hours count on no tax credit letter.
      </dd>
      <dt>Adding a team</dt>
      <dd>
        A SAR Duty admin adds and removes {@current_organization.short_name}'s teams. Reach them at <.a href="mailto:support@sarduty.com">support@sarduty.com</.a>.
      </dd>
    </dl>
    """
  end

  defp count_or_none(nil), do: "None"
  defp count_or_none(0), do: "None"
  defp count_or_none(count), do: count
end
