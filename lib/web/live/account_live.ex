defmodule Web.AccountLive do
  @moduledoc """
  Your own page: who you're logged in as, and each team's settings. Settings live under
  each team, so the URL names the team they change (#153).
  """

  use Web, :live_view_narrow_layout

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Account")}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">Account</h1>
      <p id="account-email">
        Logged in as {@current_user.email}. Your email and your teams come from D4H.
      </p>
      <nav :if={@managed_teams != []} aria-label="Team settings">
        <h2 class="subheading">Team settings</h2>
        <ul class="action-list">
          <li :for={team <- @managed_teams}>
            <.a id={"account-team-#{team.id}-settings"} navigate={~p"/teams/#{team}/settings"}>
              {team.name}
            </.a>
          </li>
        </ul>
      </nav>
    </div>
    """
  end
end
