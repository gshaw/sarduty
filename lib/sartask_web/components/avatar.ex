defmodule SartaskWeb.WebComponents.Avatar do
  use SartaskWeb, :function_component

  attr :initials, :string, required: true

  def avatar(assigns) do
    ~H"""
    <span class="inline-flex items-center justify-center rounded-full bg-brand h-8 w-8">
      <span class="leading-none font-medium text-white text-sm"><%= @initials %></span>
    </span>
    """
  end
end
