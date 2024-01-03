defmodule Web.Components.A do
  use Web, :function_component

  attr :kind, :atom,
    values: [
      :default,
      :btn,
      :custom,
      :monochrome,
      :menu_item,
      :navbar_item,
      :navbar_title
    ],
    default: :default,
    doc: "used for styling and flash lookup"

  attr :external, :boolean, default: false
  attr :is_current, :boolean, default: false
  attr :class, :any, default: ""

  attr :rest, :global,
    include: ~w(disabled href method navigate role),
    doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, required: true

  def a(assigns) do
    assigns =
      assigns
      |> assign(:link_class, determine_link_class(assigns))
      |> assign(:target, determine_target(assigns))

    ~H"""
    <.link class={@link_class} {@target} {@rest}><%= render_slot(@inner_block) %></.link>
    """
  end

  def determine_target(%{external: true}), do: %{target: "_blank"}
  def determine_target(_assigns), do: %{}

  defp determine_link_class(assigns) do
    [
      determine_kind_classes(assigns),
      determine_external_class(assigns),
      assigns.class
    ]
  end

  defp determine_external_class(%{external: true}), do: "after:content-['_↗']"
  defp determine_external_class(_assigns), do: nil

  defp determine_kind_classes(%{kind: :default}), do: ["link text-primary-1"]
  defp determine_kind_classes(%{kind: :btn}), do: ["btn"]
  defp determine_kind_classes(%{kind: :custom}), do: []
  defp determine_kind_classes(%{kind: :monochrome}), do: ["link"]

  defp determine_kind_classes(%{kind: :menu_item, is_current: is_current}) do
    [
      "block text-sm font-medium",
      "hover:text-gray-800 hover:bg-gray-200",
      "px-4 py-2",
      "focus:outline-none focus:ring-inset focus:ring-2 focus:ring-gray-800",
      is_current && "text-black font-bold",
      !is_current && "text-gray-600"
    ]
  end

  defp determine_kind_classes(%{kind: :navbar_item, is_current: is_current}) do
    [
      "border-gray-200",
      "mx-4",
      "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-800",
      is_current && "text-black",
      !is_current && "text-gray-500 hover:text-gray-800"
    ]
  end

  defp determine_kind_classes(%{kind: :navbar_title, is_current: is_current}) do
    [
      "font-medium",
      "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-800",
      is_current && "text-black",
      !is_current && "text-gray-800 hover:text-black"
    ]
  end
end
