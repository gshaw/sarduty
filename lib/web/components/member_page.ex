defmodule Web.Components.MemberPage do
  @moduledoc """
  The frame of every tab of a member's page: the header, the tabs, and the sidebar
  around the tab's own content. Members open three tabs (#440), and the frame takes
  `team_admin?` once and decides what they see: no View as member, no Equipment, Standing,
  ID card, or History tab, and no contact details or Actions.
  """
  use Web, :function_component

  import Web.Components.A
  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.ViewData.TeamAttention

  attr :member, :map, required: true
  attr :tab, :atom, required: true, doc: "the current tab, as Web.Components.MemberTabs"
  attr :last_attended_at, :any, required: true, doc: "from load_sidebar/1"
  attr :standing, :any, required: true, doc: "from load_sidebar/1"
  attr :milestones, :list, required: true, doc: "from load_sidebar/1"
  attr :equipment, :list, required: true, doc: "from load_sidebar/1"
  attr :maps_app, :string, required: true, doc: "the account's maps_app"
  attr :field_rows, :list, default: [], doc: "the member fields, from load_sidebar/1"
  attr :team_admin?, :boolean, default: false

  attr :current_member, :any,
    default: nil,
    doc: "the member logged in; on their own page a team admin is sent to Your membership"

  slot :inner_block, required: true

  def member_page(assigns) do
    ~H"""
    <.member_head
      member={@member}
      last_attended_at={@last_attended_at}
      standing={@standing}
      team_admin?={@team_admin?}
    />
    <.retiring_access_banner
      :if={@team_admin? and @standing == :retiring and Member.d4h_access?(@member)}
      member={@member}
    />
    <%!-- A team admin on their own page gets the team admin's view. What they do as a
    member is on Your membership (#645). Members are sent there by own_page. --%>
    <.banner
      :if={@team_admin? and @current_member != nil and @current_member.id == @member.id}
      class="mb-6"
      id="this-is-you"
      title="This is you"
    >
      <p>
        Log chores, add certificates, and add your ID card to Wallet on <.a navigate={
          ~p"/teams/#{@member.team}/me"
        }>Your membership</.a>.
      </p>
    </.banner>
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
          field_rows={@field_rows}
        />
      </aside>
      <main class="content-2/3">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  # SAR Duty shuts a retiring member out of itself, but only a team admin can take away
  # their access in the team's records (#514).
  attr :member, :map, required: true

  defp retiring_access_banner(assigns) do
    assigns = assign(assigns, :service, D4H.service_name(assigns.member.team))

    ~H"""
    <.banner
      kind={:danger}
      class="mb-6"
      id="retiring-access"
      title={"#{@member.name} can still log in to #{@service}"}
    >
      <p>
        They're retiring and can't log in to SAR Duty, but their {@service} access is still {Member.permission_label(
          @member.d4h_permission
        )}. {TeamAttention.no_access(D4H.service(@member.team))}
      </p>
      <p :if={!D4H.records?(@member.team)}>
        <.a external={true} href={D4H.member_url(@member)}>Open in {@service}</.a>
      </p>
      <p :if={D4H.records?(@member.team)}>
        <.a navigate={~p"/teams/#{@member.team}/members/#{@member.id}/edit"}>Change member</.a>
      </p>
    </.banner>
    """
  end

  @doc """
  Sends a member who opens their own member page to Your membership (#440), which has
  everything this page would and more. For the `on_mount` of a tab members open; a team
  admin stays. It checks on every `handle_params`, so a patch to their own id goes there
  too.
  """
  def on_mount(:own_page, _params, _session, socket),
    do: {:cont, Phoenix.LiveView.attach_hook(socket, :own_page, :handle_params, &own_page/3)}

  defp own_page(%{"id" => id}, _uri, socket) do
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
