defmodule Web.Components.Equipment do
  @moduledoc """
  Equipment's shared pieces (#490): the table of what a member holds, shown on their
  Equipment tab, on Your membership, and in Equipment's member place, and an item's
  status badge.
  """

  use Web, :function_component

  import Web.Components.A
  import Web.Components.Table

  alias App.Model.EquipmentItem

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "`%{item, inside}`, kits then their contents"
  attr :team, :map, required: true
  attr :links, :boolean, default: true, doc: "false for a member: item pages are for team admins"

  @doc """
  The items a member holds. Where says what an item is inside, and goes when nothing is
  inside another item.
  """
  def held_table(assigns) do
    assigns = assign(assigns, :where?, Enum.any?(assigns.rows, &(&1.inside != "")))

    ~H"""
    <.table id={@id} rows={@rows} row_id={&"#{@id}-#{&1.item.id}"} class="table-striped">
      <:col :let={row} label="Item">
        <.a :if={@links} navigate={~p"/teams/#{@team}/equipment/#{row.item.id}"}>{row.item.title}</.a>
        <span :if={!@links}>{row.item.title}</span>
        <.status_badge item={row.item} />
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

  attr :item, EquipmentItem, required: true

  @doc "An item's status, unless it's operational: red for unserviceable or lost."
  def status_badge(%{item: %{status: "operational"}} = assigns), do: ~H""

  def status_badge(%{item: %{status: status}} = assigns)
      when status in ["unserviceable", "lost"] do
    ~H"""
    <.badge kind={:danger}>{String.capitalize(@item.status)}</.badge>
    """
  end

  def status_badge(assigns) do
    ~H"""
    <.badge>{String.capitalize(@item.status)}</.badge>
    """
  end
end
