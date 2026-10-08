defmodule Web.Components.Breadcrumbs do
  use Web, :function_component

  import Web.Components.A

  attr :team, :any, default: nil

  slot :item do
    attr :label, :string
    attr :path, :string
  end

  # The team first, then each level; the last item is the current page and isn't a link.
  def breadcrumbs(assigns) do
    ~H"""
    <ol class="breadcrumbs">
      <li :if={@team}>
        <.a kind={:custom} navigate={~p"/teams/#{@team}"}>{@team.name}</.a>
      </li>
      <li :for={item <- @item}>
        <.icon name="hero-chevron-right-micro" class="breadcrumb-separator" />
        <%= if Map.get(item, :path) do %>
          <.a kind={:custom} navigate={item.path}>{item.label}</.a>
        <% else %>
          <span aria-current="page">{item.label}</span>
        <% end %>
      </li>
    </ol>
    """
  end

  attr :navigate, :string, required: true
  attr :rest, :global
  slot :inner_block, required: true

  # A way back for a page outside the main tree, such as settings. Name the page it goes to.
  def back_link(assigns) do
    ~H"""
    <.link navigate={@navigate} class="back-link" {@rest}>
      <.icon name="hero-chevron-left-micro" />{render_slot(@inner_block)}
    </.link>
    """
  end
end
