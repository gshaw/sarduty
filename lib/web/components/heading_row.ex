defmodule Web.Components.HeadingRow do
  @moduledoc """
  A heading with what goes beside it: a note, such as when reminders went out, and its
  action. The heading on the left, the note and action on the right, wrapping on a
  phone. The one way to put an action beside a heading (#444). See /styles/heading-row.
  """
  use Web, :function_component

  attr :id, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true, doc: "the heading, such as <h2 class=\"heading\">"
  slot :note, doc: "a short line beside the action, in hint text"
  slot :action, doc: "buttons or a link"

  def heading_row(assigns) do
    ~H"""
    <div id={@id} class={["heading-row", @class]}>
      {render_slot(@inner_block)}
      <div :if={@note != [] or @action != []} class="heading-row-end">
        <span :for={note <- @note} class="hint">{render_slot(note)}</span>
        <div :if={@action != []} class="heading-row-actions">{render_slot(@action)}</div>
      </div>
    </div>
    """
  end
end
