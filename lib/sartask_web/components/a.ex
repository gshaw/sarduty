defmodule SartaskWeb.WebComponents.A do
  use SartaskWeb, :function_component

  attr :kind, :atom,
    values: [:default, :custom, :monochrome, :menu_item, :navbar_title, :navbar_item],
    default: :default,
    doc: "used for styling and flash lookup"

  attr :external, :boolean, default: false
  attr :is_current, :boolean, default: false
  attr :class, :string, default: ""

  attr :rest, :global,
    include: ~w(href method navigate),
    doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, required: true

  def a(assigns) do
    ~H"""
    <.link
      class={[
        determine_kind_classes(@kind, @is_current),
        @class
      ]}
      {if @external, do: %{target: "_blank"}, else: %{}}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </.link>
    """
  end

  defp determine_kind_classes(:default, _is_current), do: "text-blue-600 hover:underline"
  defp determine_kind_classes(:custom, _is_current), do: nil
  defp determine_kind_classes(:monochrome, _is_current), do: "text-gray-800 hover:underline"

  defp determine_kind_classes(:menu_item, is_current) do
    "
      block text-sm font-medium
      hover:text-gray-800 hover:bg-gray-200
      px-4 py-2
      focus:outline-none focus:ring-inset focus:ring-2 focus:ring-gray-800
    " <>
      if is_current do
        "text-black font-bold"
      else
        "text-gray-600"
      end
  end

  defp determine_kind_classes(:navbar_title, is_current) do
    "
      font-medium
      focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-800
    " <>
      if is_current do
        "text-black"
      else
        "text-gray-800 hover:text-black"
      end
  end

  defp determine_kind_classes(:navbar_item, is_current) do
    "
      border-gray-200
      mx-4
      focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-800
    " <>
      if is_current do
        "text-black"
      else
        "text-gray-500 hover:text-gray-800"
      end
  end
end
