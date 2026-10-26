defmodule Web.MemberGroupsLive do
  use Web, {:live_view_app_layout, access: :team}

  on_mount {Web.Components.MemberPage, :own_page}

  import Ecto.Query
  import Web.Components.MemberPage
  import Web.Components.MemberSidebar, only: [load_sidebar: 1]

  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRule
  alias App.Model.Member
  alias App.Model.Team
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
      |> assign(:ruled_ids, ruled_ids(socket.assigns.current_team))
      |> assign(:organization_name, organization_name(socket.assigns.current_team))
      |> assign_member(member)
      |> load_sidebar()

    {:noreply, socket}
  end

  # A team admin adds to and removes from the groups kept by hand (#546); a group with
  # rules follows them. No flash: the list shows it.
  def handle_event("add-group", %{"group_id" => group_id}, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    case Enum.find(socket.assigns.other_groups, &(Integer.to_string(&1.id) == group_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a group.")}

      group ->
        case SetGroupMember.add(team, member, group, user, DateTime.utc_now()) do
          :ok -> {:noreply, reload(socket)}
          {:error, text} -> {:noreply, socket |> reload() |> put_flash(:error, text)}
        end
    end
  end

  def handle_event("remove-group", %{"id" => id}, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns
    group_member = Enum.find(member.group_members, &(Integer.to_string(&1.id) == id))

    # Gone already, say from another tab.
    result =
      if group_member,
        do: SetGroupMember.remove(team, group_member, user, DateTime.utc_now()),
        else: :ok

    case result do
      :ok -> {:noreply, reload(socket)}
      {:error, text} -> {:noreply, socket |> reload() |> put_flash(:error, text)}
    end
  end

  defp reload(socket) do
    member = find_member(socket.assigns.current_team, socket.assigns.member.id)
    socket |> clear_flash() |> assign_member(member)
  end

  defp assign_member(socket, member) do
    in_groups = MapSet.new(member.group_members, & &1.group_id)
    ruled_ids = socket.assigns.ruled_ids

    others =
      socket.assigns.current_team.id
      |> Group.get_all()
      |> Enum.reject(&(&1.id in in_groups or &1.d4h_group_id in ruled_ids))

    assign(socket, member: member, other_groups: others)
  end

  defp ruled_ids(team),
    do: team.id |> GroupRule.ruled_d4h_group_ids_query() |> Repo.all() |> MapSet.new()

  defp organization_name(team), do: Team.organization_name(team) || "Your organization"

  def render(assigns) do
    ~H"""
    <.member_page
      member={@member}
      tab={:groups}
      last_attended_at={@last_attended_at}
      standing={@standing}
      milestones={@milestones}
      equipment={@equipment}
      maps_app={@current_user.maps_app}
      team_admin?={@team_admin?}
    >
      <.groups_content
        member={@member}
        ruled_ids={@ruled_ids}
        organization_name={@organization_name}
        team_admin?={@team_admin?}
      />
      <form
        :if={@team_admin? and @other_groups != []}
        id="add-group-form"
        phx-submit="add-group"
        class="flex flex-wrap items-center gap-2 mt-4"
      >
        <.combobox
          id="add-group-id"
          name="group_id"
          value=""
          options={Enum.map(@other_groups, &{group_label(&1, @organization_name), &1.id})}
          aria-label="Group"
        />
        <.button id="add-group" phx-disable-with="Adding…">Add to group</.button>
      </form>
    </.member_page>
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
      <%!-- Plain text for a member: group pages are team admins' (#440). --%>
      <:col :let={gm} label="Group">
        <.a :if={@team_admin?} navigate={~p"/teams/#{@member.team}/groups/#{gm.group.id}"}>{gm.group.title}</.a>
        <span :if={!@team_admin?}>{gm.group.title}</span>
        <span :if={gm.group.organization_owned} class="hint">· {@organization_name}</span>
      </:col>
      <%!-- No confirm: a member has few groups, so who to add back is plain. --%>
      <:col :let={gm} :if={@team_admin?} label="" class="w-px whitespace-nowrap" align="right">
        <span :if={gm.group.d4h_group_id in @ruled_ids} class="hint">By its rules</span>
        <.button
          :if={gm.group.d4h_group_id not in @ruled_ids}
          id={"remove-group-#{gm.id}"}
          type="button"
          size={:sm}
          phx-click="remove-group"
          phx-disable-with="Removing…"
          phx-value-id={gm.id}
        >
          Remove
        </.button>
      </:col>
    </.table>
    <p :if={@member.group_members == []} id="no-groups">
      {@member.name} is not in any groups.
    </p>
    """
  end

  defp group_label(%Group{organization_owned: true} = group, organization_name),
    do: "#{group.title} · #{organization_name}"

  defp group_label(group, _organization_name), do: group.title

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
