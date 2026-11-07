defmodule Web.Components.ActionBar do
  @moduledoc """
  The bar under a long list of checked rows, with its one button. It sticks to the foot of
  the window, so the button stays in view as the list scrolls; at the list's end it sits
  under it. See /styles/action-bar.
  """
  use Phoenix.Component

  @doc """
  Renders the bar, with the button as its inner block and an optional `hint` beside it,
  such as what to do while nothing is checked. The hint's id is the bar's with `-hint`.

  ## Examples

      <.action_bar id="travel-bar" hint={if @selected == [], do: "Check members, then change their travel together."}>
        <.button variant={:primary}>Change 3 members</.button>
      </.action_bar>
  """
  attr :id, :string, required: true
  attr :hint, :string, default: nil, doc: "a line beside the button"
  attr :class, :any, default: nil
  slot :inner_block, required: true, doc: "the button"

  def action_bar(assigns) do
    ~H"""
    <div id={@id} class={["action-bar", @class]}>
      {render_slot(@inner_block)}
      <span :if={@hint} id={"#{@id}-hint"} class="hint">{@hint}</span>
    </div>
    """
  end
end
