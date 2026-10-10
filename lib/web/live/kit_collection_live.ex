defmodule Web.KitCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.Kit

  # Kits: named sets of items, with default hours, to add to an activity in one step (#271).
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    Web.EquipmentItemLive.require_equipment!(team)
    {:ok, assign(socket, page_title: "Kits", kits: Kit.get_all(team.id))}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Equipment" path={~p"/teams/#{@current_team}/equipment"} />
      <:item label="Kits" />
    </.breadcrumbs>
    <div class="heading-row">
      <h1 class="title">{@page_title}</h1>
      <.button id="kit-add" navigate={~p"/teams/#{@current_team}/equipment/kits/new"}>
        Add kit
      </.button>
    </div>
    <p class="lead">
      A kit is a set of items you add to an activity in one step, each with its usual hours.
    </p>

    <.table
      :if={@kits != []}
      id="kit_collection"
      rows={@kits}
      row_id={&"kit-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={kit} label="Kit">
        <.a navigate={~p"/teams/#{@current_team}/equipment/kits/#{kit.id}"}>{kit.title}</.a>
      </:col>
      <:col :let={kit} label="Items" class="w-px whitespace-nowrap" align="right">
        {length(kit.kit_items)}
      </:col>
    </.table>

    <.empty_state :if={@kits == []} id="no-kits" title="No kits yet">
      Add one for the gear that goes out together, such as a truck and its radios.
    </.empty_state>
    """
  end
end
