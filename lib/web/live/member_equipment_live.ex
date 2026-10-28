defmodule Web.MemberEquipmentLive do
  use Web, :live_view_app_layout

  import Web.Components.Equipment, only: [held_table: 1]
  import Web.Components.MemberPage
  import Web.Components.MemberSidebar, only: [load_sidebar: 1]

  alias App.Model.Member
  alias App.Repo
  alias App.ViewData.EquipmentList

  # A member's Equipment tab (#490): everything they hold, each kit followed by what's
  # inside it, so a team admin sees what to get back. The tab shows only when they hold
  # something; the list is the one Your membership and Equipment's member place show.
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = socket.assigns.current_team |> Member.find!(params["id"]) |> Repo.preload(:team)

    socket =
      socket
      |> assign(:page_title, "#{member.name} · Equipment")
      |> assign(:member, member)
      |> load_sidebar()

    {:noreply, assign(socket, :rows, EquipmentList.held_rows(socket.assigns.equipment))}
  end

  def render(assigns) do
    ~H"""
    <.member_page
      current_member={@current_member}
      member={@member}
      tab={:equipment}
      last_attended_at={@last_attended_at}
      standing={@standing}
      milestones={@milestones}
      equipment={@equipment}
      maps_app={@current_user.maps_app}
      team_admin?={@team_admin?}
    >
      <.empty_state :if={@rows == []} id="no-member-equipment" title="No equipment">
        Items placed with {@member.name} show here.
      </.empty_state>
      <.held_table :if={@rows != []} id="member-equipment-list" rows={@rows} team={@member.team} />
    </.member_page>
    """
  end
end
