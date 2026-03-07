defmodule Web.GroupCollectionLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Groups")}
  end

  def handle_params(_params, _uri, socket) do
    current_team = socket.assigns.current_team
    groups = list_groups_with_counts(current_team)

    socket =
      socket
      |> assign(:groups, groups)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team} />
    <h1 class="title mb-p">{@page_title}</h1>

    <p class="mb-p text-secondary-1 text-sm">{length(@groups)} groups</p>

    <.table id="group_collection" rows={@groups} class="w-full table-striped">
      <:col :let={g} label="Group">
        <.a navigate={~p"/#{@current_team.subdomain}/groups/#{g.id}"}>{g.title}</.a>
      </:col>
      <:col :let={g} label="Members" class="w-px whitespace-nowrap" align="right">
        {g.member_count}
      </:col>
    </.table>

    <p :if={@groups == []} class="text-secondary-1">No groups found.</p>
    """
  end

  defp list_groups_with_counts(team) do
    Group
    |> where([g], g.team_id == ^team.id)
    |> join(:left, [g], gm in GroupMember, on: gm.group_id == g.id)
    |> group_by([g], [g.id, g.title])
    |> order_by([g], asc: g.title)
    |> select([g, gm], %{
      id: g.id,
      title: g.title,
      member_count: count(gm.id)
    })
    |> Repo.all()
  end
end
