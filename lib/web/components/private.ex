defmodule Web.Components.Private do
  @moduledoc """
  Contact details blurred until tapped, so they can't be read off a shared or projected
  screen, or over a shoulder. It blurs the `.private-text` inside: a copy button's text
  is one, and its button still copies while blurred. The first tap on blurred text only
  shows it, even on a mailto: link; the next follows the link. Each page load blurs it
  again. The details are still in the page: it hides them from eyes, not from the
  viewer. See /styles/private.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def private(assigns) do
    ~H"""
    <span
      id={@id}
      class={["private", @class]}
      data-private="hidden"
      data-reveal={JS.set_attribute({"data-private", "shown"})}
    >{render_slot(@inner_block)}</span>
    """
  end
end
