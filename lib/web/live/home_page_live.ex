defmodule Web.HomePageLive do
  use Web, :live_view_marketing_layout

  alias App.Model.Team

  def mount(_params, _session, socket) do
    teams =
      case socket.assigns.current_user do
        nil -> []
        user -> Team.get_managed_by(user.email, DateTime.utc_now())
      end

    {:ok, assign(socket, page_title: "Welcome", teams: teams)}
  end

  def render(assigns) do
    ~H"""
    <div class="mb-8">
      <h1 class="title-hero">
        Welcome to <span>SAR{Service.StringHelpers.no_break_space()}Duty</span>
      </h1>
      <p class="lead">
        Helpful tools for search and rescue managers.
      </p>
    </div>
    <ul :if={@teams != []} id="my-teams" class="heading action-list">
      <li :for={team <- @teams}>
        <.a navigate={~p"/#{team.subdomain}"}>{team.name}</.a>
      </li>
    </ul>
    <p :if={@current_user && @teams == []} id="no-teams">
      Your email isn't an Owner or Editor on any team SAR Duty knows. Access comes from D4H:
      check the email D4H has for you, or ask one of your team's D4H owners.
    </p>
    """
  end
end
