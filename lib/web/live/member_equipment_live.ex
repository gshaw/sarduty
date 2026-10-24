defmodule Web.MemberEquipmentLive do
  use Web, :live_view_app_layout

  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Repo
  alias App.ViewData.EquipmentList
  alias Web.EquipmentCollectionLive

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
    <.member_head member={@member} last_attended_at={@last_attended_at} standing={@standing} />
    <.member_tabs member={@member} active_tab={:equipment} equipment={@equipment} />
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content
          member={@member}
          maps_app={@current_user.maps_app}
          milestones={@milestones}
          equipment={@equipment}
        />
      </aside>
      <main class="content-2/3">
        <.empty_state :if={@rows == []} id="no-member-equipment" title="No equipment">
          Items {D4H.service_name(@member.team)} puts with {@member.name} show here.
        </.empty_state>
        <.held_table :if={@rows != []} id="member-equipment-list" rows={@rows} team={@member.team} />
      </main>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "`%{item, inside}`, kits then their contents"
  attr :team, :map, required: true
  attr :links, :boolean, default: true, doc: "false for a member: item pages are for team admins"

  @doc """
  The items a member holds, as the member's Equipment tab, Your membership, and
  Equipment's member place show them. Where says what an item is inside, and goes when
  nothing is inside another item.
  """
  def held_table(assigns) do
    assigns = assign(assigns, :where?, Enum.any?(assigns.rows, &(&1.inside != "")))

    ~H"""
    <.table id={@id} rows={@rows} row_id={&"#{@id}-#{&1.item.id}"} class="table-striped">
      <:col :let={row} label="Item">
        <.a :if={@links} navigate={~p"/teams/#{@team}/equipment/#{row.item.id}"}>{row.item.title}</.a>
        <span :if={!@links}>{row.item.title}</span>
        <EquipmentCollectionLive.status_badge item={row.item} />
      </:col>
      <:col :let={row} :if={@where?} label="Where">{row.inside}</:col>
      <:col :let={row} label="Category">{row.item.kind}</:col>
      <:col :let={row} label="Barcode" class="w-px whitespace-nowrap">{row.item.barcode}</:col>
      <:col :let={row} label="Expires" align="right" class="w-px whitespace-nowrap">
        <span :if={row.item.expires_at}>
          {Service.Format.date_short(row.item.expires_at, @team.timezone)}
        </span>
      </:col>
    </.table>
    """
  end
end
