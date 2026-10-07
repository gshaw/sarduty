defmodule Web.MemberHistoryLive do
  use Web, :live_view_app_layout

  import Web.Components.ChangeHistory
  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

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
      |> assign(:entries, ChangeHistory.for_member(team, member))

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Members" path={~p"/teams/#{@current_team}/members/"} />
      <:item label="History" />
    </.breadcrumbs>

    <h1 class="title">{@member.name}</h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content member={@member} />
      </aside>
      <main class="content-2/3">
        <.member_tabs member={@member} active_tab={:history} />
        <.change_history id="member-history" entries={@entries} timezone={@current_team.timezone} />
      </main>
    </div>
    """
  end
end
