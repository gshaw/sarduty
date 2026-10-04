defmodule Web.Components.A do
  use Web, :function_component

  attr :kind, :atom,
    values: [:default, :custom, :monochrome],
    default: :default,
    doc: "default is an underlined link, monochrome is in the text colour, custom is unstyled"

  attr :external, :boolean, default: false
  attr :class, :any, default: ""

  attr :rest, :global,
    include: ~w(disabled href method navigate role target),
    doc: "the arbitrary HTML attributes to add to the link"

  slot :inner_block, required: true

  def a(assigns) do
    assigns =
      assigns
      |> assign(:link_class, determine_link_class(assigns))
      |> assign(:link_target, determine_target(assigns))

    ~H"""
    <.link class={@link_class} target={@link_target} {@rest}>
      {render_slot(@inner_block)}<.icon
        :if={@external}
        name="hero-arrow-top-right-on-square-micro"
        class="size-4 ml-0.5 align-[-3px]"
      />
    </.link>
    """
  end

  defp determine_target(%{external: true}), do: "_blank"
  defp determine_target(_assigns), do: nil

  defp determine_link_class(assigns) do
    [determine_kind_classes(assigns), assigns.class]
  end

  defp determine_kind_classes(%{kind: :default}), do: ["link"]
  defp determine_kind_classes(%{kind: :custom}), do: []
  defp determine_kind_classes(%{kind: :monochrome}), do: ["link text-base-content"]
end
