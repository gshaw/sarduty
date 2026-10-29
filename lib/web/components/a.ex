defmodule Web.Components.A do
  use Web, :function_component

  attr :kind, :atom,
    values: [:default, :custom, :monochrome],
    default: :default,
    doc: "default is an underlined link, monochrome is in the text colour, custom is unstyled"

  attr :external, :boolean, default: false

  attr :icon, :string,
    default: nil,
    doc: "an icon in the arrow's place, for an action that has one, such as calendar-plus"

  attr :class, :any, default: ""

  attr :rest, :global,
    include: ~w(disabled href method navigate patch role target),
    doc: "the arbitrary HTML attributes to add to the link"

  slot :inner_block, required: true

  def a(assigns) do
    assigns = assign(assigns, :link_class, determine_link_class(assigns))
    render_link(assigns)
  end

  defp render_link(%{external: true} = assigns) do
    ~H"""
    <.link class={@link_class} target="_blank" {@rest}><.icon
      :if={@icon}
      name={@icon}
      size={:sm}
      class="link-mark"
    /><span class="link-text">{render_slot(@inner_block)}</span><.icon
      name={external_icon()}
      size={:sm}
      class="link-icon"
    /></.link>
    """
  end

  defp render_link(assigns) do
    ~H"""
    <.link class={@link_class} {@rest}><.icon
      :if={@icon}
      name={@icon}
      size={:sm}
      class="link-mark"
    />{render_slot(@inner_block)}</.link>
    """
  end

  defp external_icon, do: "external-link"

  defp determine_link_class(assigns) do
    [determine_kind_classes(assigns), assigns.icon && "has-mark", assigns.class]
  end

  defp determine_kind_classes(%{kind: :default}), do: ["link"]
  defp determine_kind_classes(%{kind: :custom}), do: []
  defp determine_kind_classes(%{kind: :monochrome}), do: ["link text-text"]
end
