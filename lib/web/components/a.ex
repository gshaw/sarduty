defmodule Web.WebComponents.A do
  use Web, :function_component

  attr :kind, :atom,
    values: [
      :default,
      :custom,
      :monochrome,
      :menu_item,
      :navbar_item,
      :navbar_title
    ],
    default: :default,
    doc: "used for styling and flash lookup"

  attr :external, :boolean, default: false
  attr :external_icon_class, :string, default: nil
  attr :is_current, :boolean, default: false
  attr :class, :any, default: ""

  attr :rest, :global,
    include: ~w(disabled href method navigate role),
    doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, required: true

  def a(assigns) do
    ~H"""
    <.link
      class={determine_kind_classes(@kind, @is_current) ++ [@class]}
      {if @external, do: %{target: "_blank"}, else: %{}}
      {@rest}
      phx-no-format
    ><%= render_slot(@inner_block) %><%= if @external do %><.icon
      name="hero-arrow-top-right-on-square-mini"
      class={"ml-1 mb-1 w-5 h-5 #{@external_icon_class}"}
    /><% end %></.link>
    """
  end

  defp determine_kind_classes(:default, _is_current), do: ["link link-primary"]
  defp determine_kind_classes(:custom, _is_current), do: []
  defp determine_kind_classes(:monochrome, _is_current), do: ["link"]

  defp determine_kind_classes(:menu_item, is_current) do
    [
      "block text-sm font-medium",
      "hover:text-gray-800 hover:bg-gray-200",
      "px-4 py-2",
      "focus:outline-none focus:ring-inset focus:ring-2 focus:ring-gray-800",
      is_current && "text-black font-bold",
      !is_current && "text-gray-600"
    ]
  end

  defp determine_kind_classes(:navbar_item, is_current) do
    [
      "border-gray-200",
      "mx-4",
      "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-800",
      is_current && "text-black",
      !is_current && "text-gray-500 hover:text-gray-800"
    ]
  end

  defp determine_kind_classes(:navbar_title, is_current) do
    [
      "font-medium",
      "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-800",
      is_current && "text-black",
      !is_current && "text-gray-800 hover:text-black"
    ]
  end
end
