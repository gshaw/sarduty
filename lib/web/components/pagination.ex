defmodule Web.Components.Pagination do
  use Web, :function_component

  import Web.Components.A

  attr :paginated, :map, required: true
  attr :path_fn, :any, required: true
  attr :class, :string, default: nil

  def pagination(assigns) do
    ~H"""
    <nav :if={@paginated.total_pages > 1} class={["pagination", @class]} aria-label="Pages">
      <%= if @paginated.page_number > 1 do %>
        <.a kind={:custom} navigate={@path_fn.(page: @paginated.page_number - 1)} class="link"><.icon
          name="chevron-left"
          size={:sm}
        />Previous</.a>
      <% else %>
        <span class="pagination-disabled">
          <.icon name="chevron-left" size={:sm} />Previous
        </span>
      <% end %>
      <span>Page {@paginated.page_number} of {@paginated.total_pages}</span>
      <%= if @paginated.page_number < @paginated.total_pages do %>
        <.a kind={:custom} navigate={@path_fn.(page: @paginated.page_number + 1)} class="link">Next<.icon
          name="chevron-right"
          size={:sm}
        /></.a>
      <% else %>
        <span class="pagination-disabled">
          Next<.icon name="chevron-right" size={:sm} />
        </span>
      <% end %>
    </nav>
    """
  end
end
