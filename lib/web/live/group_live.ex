defmodule Web.GroupLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    current_team = socket.assigns.current_team
    group = find_group(params["id"], current_team.id)
    members = list_members_for_group(group)

    socket =
      socket
      |> assign(:page_title, group.title)
      |> assign(:group, group)
      |> assign(:members, members)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Groups" path={~p"/#{@current_team.subdomain}/groups"} />
      <:item label={@group.title} />
    </.breadcrumbs>

    <h1 class="title">{@group.title}</h1>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content group={@group} members={@members} team={@current_team} />
      </aside>
      <main class="content-2/3">
        <.main_content members={@members} team={@current_team} />
      </main>
    </div>
    """
  end

  defp sidebar_content(assigns) do
    ~H"""
    <dl>
      <dt>Actions</dt>
      <dd>
        <ul class="action-list">
          <li>
            <.a external={true} href={D4H.build_url(@team, "/team/members")}>
              Open D4H Members
            </.a>
          </li>
        </ul>
      </dd>
      <dt>Members</dt>
      <dd>{length(@members)}</dd>
    </dl>
    """
  end

  defp main_content(assigns) do
    ~H"""
    <h2 class="subtitle mb-p05">Members ({length(@members)})</h2>
    <.table
      :if={@members != []}
      id="group_members"
      rows={@members}
      class="w-full table-striped"
    >
      <:col :let={gm} label="Member">
        <.a navigate={~p"/#{@team.subdomain}/members/#{gm.member.id}"}>
          {gm.member.name}
        </.a>
      </:col>
    </.table>
    <p :if={@members == []} class="text-secondary-1">No members found.</p>
    """
  end

  defp find_group(id, team_id) do
    Group
    |> where([g], g.id == ^id and g.team_id == ^team_id)
    |> Repo.one!()
  end

  defp list_members_for_group(group) do
    GroupMember
    |> where([gm], gm.group_id == ^group.id)
    |> join(:inner, [gm], m in assoc(gm, :member))
    |> order_by([gm, m], asc: m.name)
    |> preload([gm, m], member: m)
    |> Repo.all()
  end
end
