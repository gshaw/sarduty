defmodule Web.Components.DragList do
  @moduledoc """
  Rows people put in order (#1056): a team's fields on Change order, a field's choices on
  Change field, and next equipment checklists (#407). See `/styles/drag-list`.

  Each row has a grip handle. Drag it, with a mouse or a finger. On the keyboard the
  handle moves its row with the up and down arrows, and `moves` adds Move up and Move
  down buttons for a list where ordering is the whole page. The `DragList` hook moves the
  row at once and sends `event` with `%{"keys" => keys}`, every row's key in the new
  order. The LiveView puts its list in that order with `reorder/3` and renders it, so the
  server always holds the order a save sends.
  """
  use Web, :function_component

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :key, :any, required: true, doc: "a function from a row to its key, a string"
  attr :label, :any, required: true, doc: "a function from a row to its name, for the handle"
  attr :event, :string, required: true
  attr :moves, :boolean, default: false, doc: "Move up and Move down buttons on each row"
  attr :class, :any, default: nil
  slot :inner_block, required: true, doc: "the row's content, given the row"
  slot :actions, doc: "buttons at the row's end, given the row"

  def drag_list(assigns) do
    assigns = assign(assigns, :count, length(assigns.rows))

    ~H"""
    <div id={@id} class={["drag-list", @class]} phx-hook="DragList" data-event={@event}>
      <p id={"#{@id}-how"} class="sr-only">
        Drag to move. Or press the up or down arrow.
      </p>
      <ol class="drag-rows">
        <li
          :for={{row, index} <- Enum.with_index(@rows)}
          id={"#{@id}-row-#{@key.(row)}"}
          class="drag-row"
          data-key={@key.(row)}
          data-label={@label.(row)}
        >
          <button
            type="button"
            class="drag-handle"
            data-drag-handle
            aria-label={"Move #{@label.(row)}"}
            aria-describedby={"#{@id}-how"}
          >
            <.icon name="grip-vertical" />
          </button>
          <div class="drag-row-body">{render_slot(@inner_block, row)}</div>
          <.button
            :if={@moves}
            type="button"
            size={:sm}
            data-move="up"
            disabled={index == 0}
            aria-label={"Move #{@label.(row)} up"}
          >
            Move up
          </.button>
          <.button
            :if={@moves}
            type="button"
            size={:sm}
            data-move="down"
            disabled={index == @count - 1}
            aria-label={"Move #{@label.(row)} down"}
          >
            Move down
          </.button>
          {render_slot(@actions, row)}
        </li>
      </ol>
      <p class="sr-only" aria-live="polite" data-drag-status></p>
    </div>
    """
  end

  @doc """
  `rows` in the order of `keys`, the keys the hook sent, with `key` the function the list
  was drawn with. `:error` when `keys` don't name each row once: the list changed.
  """
  def reorder(rows, keys, key) when is_list(keys) do
    by_key = Map.new(rows, &{key.(&1), &1})

    if Enum.sort(keys) == by_key |> Map.keys() |> Enum.sort(),
      do: {:ok, Enum.map(keys, &Map.fetch!(by_key, &1))},
      else: :error
  end

  def reorder(_rows, _keys, _key), do: :error
end
