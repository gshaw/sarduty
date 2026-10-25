defmodule Web.Components.MemberPage do
  @moduledoc """
  The frame of every tab of a member's page: the header, the tabs, and the sidebar
  around the tab's own content. Members open three tabs (#440), and the frame takes
  `team_admin?` once and decides what they see: no View as member, no Equipment, Standing,
  ID card, or History tab, and no contact details or Actions.
  """
  use Web, :function_component

  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  attr :member, :map, required: true
  attr :tab, :atom, required: true, doc: "the current tab, as Web.Components.MemberTabs"
  attr :last_attended_at, :any, required: true, doc: "from load_sidebar/1"
  attr :standing, :any, required: true, doc: "from load_sidebar/1"
  attr :milestones, :list, required: true, doc: "from load_sidebar/1"
  attr :equipment, :list, required: true, doc: "from load_sidebar/1"
  attr :maps_app, :string, required: true, doc: "the account's maps_app"
  attr :team_admin?, :boolean, default: false
  slot :inner_block, required: true

  def member_page(assigns) do
    ~H"""
    <.member_head
      member={@member}
      last_attended_at={@last_attended_at}
      standing={@standing}
      team_admin?={@team_admin?}
    />
    <.member_tabs
      member={@member}
      active_tab={@tab}
      equipment={@equipment}
      team_admin?={@team_admin?}
    />
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content
          member={@member}
          maps_app={@maps_app}
          milestones={@milestones}
          team_admin?={@team_admin?}
        />
      </aside>
      <main class="content-2/3">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  @doc """
  Sends a member who opens their own member page to Your membership (#440), which has
  everything this page would and more. For the `on_mount` of a tab members open; a team
  admin stays.
  """
  def on_mount(:own_page, %{"id" => id}, _session, socket) do
    case socket.assigns do
      %{team_admin?: false, current_member: %{id: member_id}, current_team: team} ->
        if id == Integer.to_string(member_id),
          do: {:halt, Phoenix.LiveView.push_navigate(socket, to: ~p"/teams/#{team}/me")},
          else: {:cont, socket}

      _assigns ->
        {:cont, socket}
    end
  end
end
