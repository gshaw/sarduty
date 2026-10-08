defmodule Web.Components.Verify do
  @moduledoc """
  The blocks shared by the verify site's pages for ID cards and letters. The result itself
  is a `<.band>` from `Web.Components.Messages`.
  """
  use Web, :function_component

  slot :inner_block, required: true

  # The details under the result: a card.
  def panel(assigns) do
    ~H"""
    <div class="card mt-4">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def fact(assigns) do
    ~H"""
    <div class={@class}>
      <div class="caps">{@label}</div>
      <div class="text-lg font-semibold">{render_slot(@inner_block)}</div>
    </div>
    """
  end
end
