defmodule Web.MemberFieldsLive do
  @moduledoc """
  A member's Fields tab (#705): the D4H member fields the team copies (#681), team admins
  only, as the member's contact details are, with Change fields. A member sees their own
  on Your membership.
  """
  use Web, :live_view_app_layout

  import Web.Components.CustomFields
  import Web.Components.MemberPage
  import Web.Components.MemberSidebar, only: [load_sidebar: 1]

  alias App.Model.Member
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    member = team |> Member.find!(params["id"]) |> Repo.preload(:team)

    socket =
      socket
      |> assign(:page_title, "#{member.name} · Fields")
      |> assign(:member, member)
      |> load_sidebar()

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.member_page
      current_member={@current_member}
      member={@member}
      tab={:fields}
      last_attended_at={@last_attended_at}
      standing={@standing}
      milestones={@milestones}
      equipment={@equipment}
      fields?={@fields?}
      maps_app={@current_user.maps_app}
      team_admin?={@team_admin?}
    >
      <.custom_fields_table id="member-fields" rows={@field_rows} />
      <p class="action">
        <.a
          id="member-fields-change"
          navigate={~p"/teams/#{@member.team}/members/#{@member.id}/fields/edit"}
        >Change fields</.a>
      </p>
    </.member_page>
    """
  end
end
