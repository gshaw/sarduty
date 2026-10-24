defmodule Web.MemberHistoryLive do
  use Web, :live_view_app_layout

  import Web.Components.ChangeHistory
  import Web.Components.MemberPage
  import Web.Components.MemberSidebar, only: [load_sidebar: 1]

  alias App.Model.Member
  alias App.Repo
  alias App.ViewData.ChangeHistory

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    member = team |> Member.find!(params["id"]) |> Repo.preload(:team)

    socket =
      socket
      |> assign(:page_title, "#{member.name} · History")
      |> assign(:member, member)
      |> load_sidebar()
      |> assign(:entries, ChangeHistory.for_member(team, member))

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.member_page
      member={@member}
      tab={:history}
      last_attended_at={@last_attended_at}
      standing={@standing}
      milestones={@milestones}
      maps_app={@current_user.maps_app}
      team_admin?={@team_admin?}
    >
      <.change_history id="member-history" entries={@entries} timezone={@current_team.timezone} />
    </.member_page>
    """
  end
end
