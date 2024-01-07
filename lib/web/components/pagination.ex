defmodule Web.Components.Pagination do
  use Web, :function_component

  import Web.Components.A

  attr :paginated, :map, required: true
  attr :path_fn, :any, required: true
  attr :class, :string, default: nil

  def pagination(assigns) do
    ~H"""
    <nav
      :if={@paginated.total_pages > 1}
      class={["flex items-center justify-between gap-hspacer", @class]}
      aria-label="pagination"
    >
      <%= if @paginated.page_number > 1 do %>
        <.a navigate={@path_fn.(page: @paginated.page_number - 1)}>← Previous Page</.a>
      <% else %>
        <span class="text-disabled">← Previous Page</span>
      <% end %>
      <span>
        Page <%= @paginated.page_number %> of <%= @paginated.total_pages %>
      </span>
      <%= if @paginated.page_number < @paginated.total_pages do %>
        <.a navigate={@path_fn.(page: @paginated.page_number + 1)}>Next Page →</.a>
      <% else %>
        <span class="text-disabled">Next Page →</span>
      <% end %>
    </nav>
    """
  end
end
