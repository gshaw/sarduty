defmodule Web.MemberGroupsLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = find_member(params["id"])

    socket =
      socket
      |> assign(:page_title, "#{member.name} - Groups")
      |> assign(:member, member)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Members" path={~p"/#{@current_team.subdomain}/members/"} />
      <:item label="Groups" />
    </.breadcrumbs>

    <h1 class="title">{@member.name}</h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content member={@member} />
      </aside>
      <main class="content-2/3">
        <.member_tabs member={@member} active_tab={:groups} />
        <.groups_content member={@member} />
      </main>
    </div>
    """
  end

  defp groups_content(assigns) do
    ~H"""
    <.table
      :if={@member.group_members != []}
      id="member_groups"
      rows={@member.group_members}
      class="w-full table-striped"
    >
      <:col :let={gm} label="Group">
        <.a navigate={~p"/#{@member.team.subdomain}/groups/#{gm.group.id}"}>
          {gm.group.title}
        </.a>
      </:col>
    </.table>
    <p :if={@member.group_members == []}>No groups found.</p>
    """
  end

  defp find_member(member_id) do
    group_members_query =
      from(gm in GroupMember,
        join: g in assoc(gm, :group),
        order_by: [asc: g.title],
        preload: [group: g]
      )

    Member
    |> Repo.get(member_id)
    |> Repo.preload([
      :team,
      group_members: group_members_query
    ])
  end
end
