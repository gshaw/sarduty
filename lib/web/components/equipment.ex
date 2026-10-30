defmodule Web.Components.Equipment do
  @moduledoc """
  Equipment's shared pieces (#490): the table of what a member holds, shown on their
  Equipment tab, on Your membership, and in Equipment's member place.
  """

  use Web, :function_component

  import Web.Components.Columns
  import Web.Components.Table

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
        <.item_cell item={row.item} team={@team} link={@links} />
      </:col>
      <:col :let={row} :if={@where?} label="Where">{row.inside}</:col>
      <:col :let={row} label="Category">{row.item.kind}</:col>
      <:col :let={row} label="Barcode" class="w-px whitespace-nowrap">{row.item.barcode}</:col>
      <:col :let={row} label="Expires" class="w-px whitespace-nowrap">
        <.expires_cell value={row.item.expires_at} timezone={@team.timezone} />
      </:col>
    </.table>
    """
  end
end
