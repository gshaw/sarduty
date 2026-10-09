defmodule Web.Admin.IdCardsLive do
  use Web, :live_view_app_layout

  import Web.Components.AdminTabs

  alias App.Adapter.D4H
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.SetTeamIdCards

  # Which teams may issue ID cards. A card verifies on SAR Duty's verify site, and anyone
  # can sign up a team on SAR Duty Records, so an admin checks a team before turning
  # this on.
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "ID cards") |> assign_data()}
  end

  defp assign_data(socket),
    do: assign(socket, teams: Team.get_all(), card_counts: MemberCard.count_live_by_team())

  def handle_event("set", %{"team-id" => team_id, "enabled" => enabled}, socket) do
    team = Enum.find(socket.assigns.teams, &(Integer.to_string(&1.id) == team_id))
    if is_nil(team), do: raise(Web.Status.NotFound)

    {:ok, team} = SetTeamIdCards.call(team, enabled == "true", socket.assigns.current_user)

    message =
      if team.id_cards_enabled,
        do: "ID cards turned on for #{team.name}.",
        else: "ID cards turned off for #{team.name}. Its cards are cancelled."

    {:noreply, socket |> assign_data() |> put_flash(:info, message)}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">Admin</h1>
    <.admin_tabs current={:id_cards} />
    <p class="mb-4 max-w-3xl">
      A team issues ID cards only once this is on. Anyone can verify a card on {Web.VerifyHost.host()}, and anyone can sign up a team on SAR Duty Records, so check
      that a team is real before turning it on. Turning it off cancels every card on the
      team.
    </p>
    <.table id="id-card-teams" rows={@teams} row_id={&"id-card-team-#{&1.id}"} class="table-striped">
      <:col :let={team} label="Team">
        <.a navigate={~p"/teams/#{team}"}>{team.name}</.a>
      </:col>
      <:col :let={team} label="Records">{D4H.service_name(team)}</:col>
      <:col :let={team} label="ID cards">
        <span :if={team.id_cards_enabled} class="text-success-text">On</span>
        <span :if={!team.id_cards_enabled} class="text-text-muted">Off</span>
      </:col>
      <:col :let={team} label="Cards">{Map.get(@card_counts, team.id, 0)}</:col>
      <:col :let={team} label="">
        <.button
          :if={!team.id_cards_enabled}
          id={"id-cards-on-#{team.id}"}
          type="button"
          size={:sm}
          phx-click="set"
          phx-value-team-id={team.id}
          phx-value-enabled="true"
        >
          Turn on ID cards
        </.button>
        <.button
          :if={team.id_cards_enabled}
          id={"id-cards-off-#{team.id}"}
          type="button"
          size={:sm}
          variant={:danger}
          phx-click="set"
          phx-value-team-id={team.id}
          phx-value-enabled="false"
          data-confirm={"Turn off ID cards for #{team.name}? This cancels its #{Service.Format.count(Map.get(@card_counts, team.id, 0), one: "%d card", many: "%d cards")}."}
        >
          Turn off ID cards
        </.button>
      </:col>
    </.table>
    """
  end
end
