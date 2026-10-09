defmodule Web.MemberGroupsLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Operation.SetGroupMember
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = find_member(socket.assigns.current_team, params["id"])

    socket =
      socket
      |> assign(:page_title, "#{member.name} · Groups")
      |> assign(:hosted?, D4H.hosted?(socket.assigns.current_team))
      |> assign_member(member)

    {:noreply, socket}
  end

  # Adding to and removing from groups, for a hosted team (docs/hosted-d4h.md).
  def handle_event("add-group", %{"group_id" => group_id}, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns
    true = socket.assigns.hosted?

    case Enum.find(socket.assigns.other_groups, &(Integer.to_string(&1.id) == group_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a group.")}

      group ->
        case SetGroupMember.add(team, member, group, user, DateTime.utc_now()) do
          :ok -> {:noreply, reload(socket, "Added to #{group.title}.")}
          {:error, text} -> {:noreply, put_flash(socket, :error, text)}
        end
    end
  end

  def handle_event("remove-group", %{"id" => id}, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns
    true = socket.assigns.hosted?
    group_member = Enum.find(member.group_members, &(Integer.to_string(&1.id) == id))

    # Gone already, say from another tab.
    result =
      if group_member,
        do: SetGroupMember.remove(team, group_member, user, DateTime.utc_now()),
        else: :gone

    case result do
      :ok -> {:noreply, reload(socket, "Removed from #{group_member.group.title}.")}
      :gone -> {:noreply, reload(socket, "#{member.name} left that group already.")}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp reload(socket, text) do
    member = find_member(socket.assigns.current_team, socket.assigns.member.id)
    socket |> put_flash(:info, text) |> assign_member(member)
  end

  defp assign_member(socket, member) do
    in_groups = MapSet.new(member.group_members, & &1.group_id)

    others =
      socket.assigns.current_team.id |> Group.get_all() |> Enum.reject(&(&1.id in in_groups))

    assign(socket, member: member, other_groups: others)
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Members" path={~p"/teams/#{@current_team}/members/"} />
      <:item label="Groups" />
    </.breadcrumbs>

    <h1 class="title">{@member.name}</h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content member={@member} />
      </aside>
      <main class="content-2/3">
        <.member_tabs member={@member} active_tab={:groups} />
        <.groups_content member={@member} hosted?={@hosted?} />
        <form
          :if={@hosted? and @other_groups != []}
          id="add-group-form"
          phx-submit="add-group"
          class="mt-8 max-w-xl"
        >
          <h2 class="heading">Add to a group</h2>
          <.input
            name="group_id"
            id="add-group-id"
            type="select"
            label="Group"
            value=""
            prompt="Select a group"
            options={Enum.map(@other_groups, &{&1.title, &1.id})}
          />
          <.form_actions>
            <.button variant={:success}>Add to group</.button>
          </.form_actions>
        </form>
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
      class="table-striped"
    >
      <:col :let={gm} label="Group">
        <.a navigate={~p"/teams/#{@member.team}/groups/#{gm.group.id}"}>
          {gm.group.title}
        </.a>
      </:col>
      <:col :let={gm} :if={@hosted?} label="" class="w-px whitespace-nowrap">
        <.button
          id={"remove-group-#{gm.id}"}
          type="button"
          variant={:link}
          size={:sm}
          phx-click="remove-group"
          phx-value-id={gm.id}
          data-confirm={"Remove #{@member.name} from #{gm.group.title}?"}
        >
          Remove
        </.button>
      </:col>
    </.table>
    <p :if={@member.group_members == []} id="no-groups">
      {@member.name} is not in any {if !@hosted?, do: "D4H "}groups.
    </p>
    """
  end

  defp find_member(team, member_id) do
    group_members_query =
      from(gm in GroupMember,
        join: g in assoc(gm, :group),
        order_by: [asc: g.title],
        preload: [group: g]
      )

    team
    |> Member.find!(member_id)
    |> Repo.preload([
      :team,
      group_members: group_members_query
    ])
  end
end
