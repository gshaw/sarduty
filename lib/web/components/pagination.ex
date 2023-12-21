defmodule Web.WebComponents.Pagination do
  use Web, :function_component

  import Web.WebComponents.A

  attr :page, :map, required: true
  attr :path, :string, required: true
  attr :class, :string, default: nil

  def pagination(assigns) do
    ~H"""
    <div :if={@page.total_pages > 1} class={["flex items-center justify-between", @class]}>
      <%= if @page.page_number > 1 do %>
        <.a navigate={"#{@path}?page=#{@page.page_number - 1}"}>← Previous Page</.a>
      <% else %>
        <span class="text-disabled">← Previous Page</span>
      <% end %>
      <span class="px-2">
        Page <%= @page.page_number %> of <%= @page.total_pages %>
      </span>
      <%= if @page.page_number < @page.total_pages do %>
        <.a navigate={"#{@path}?page=#{@page.page_number + 1}"}>Next Page →</.a>
      <% else %>
        <span class="text-disabled">Next Page →</span>
      <% end %>
    </div>
    """
  end
end
