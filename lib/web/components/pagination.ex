defmodule Web.WebComponents.Pagination do
  use Web, :function_component

  import Web.WebComponents.A

  attr :page, :map, required: true
  attr :page_path_fn, :any, required: true
  attr :class, :string, default: nil

  def pagination(assigns) do
    ~H"""
    <nav
      :if={@page.total_pages > 1}
      class={["flex items-center justify-between", @class]}
      aria-label="pagination"
    >
      <%= if @page.page_number > 1 do %>
        <.a navigate={@page_path_fn.(@page.page_number - 1)}>← Previous Page</.a>
      <% else %>
        <span class="text-disabled">← Previous Page</span>
      <% end %>
      <span class="px-2">
        Page <%= @page.page_number %> of <%= @page.total_pages %>
      </span>
      <%= if @page.page_number < @page.total_pages do %>
        <.a navigate={@page_path_fn.(@page.page_number + 1)}>Next Page →</.a>
      <% else %>
        <span class="text-disabled">Next Page →</span>
      <% end %>
    </nav>
    """
  end
end
