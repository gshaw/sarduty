defmodule Web.Components.RowLink do
  use Web, :function_component

  attr :navigate, :string, required: true
  attr :rest, :global
  slot :inner_block, required: true

  # A row in a list that goes to one place. The whole row is the link, at least 44px tall,
  # with a chevron at the end. Give the row's title `text-link` so it reads as a link.
  def row_link(assigns) do
    ~H"""
    <.link navigate={@navigate} class="row-link" {@rest}>
      <span class="row-link-body">{render_slot(@inner_block)}</span>
      <.icon name="hero-chevron-right-micro" class="row-link-chevron" />
    </.link>
    """
  end
end
