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
        <.a kind={:custom} navigate={~p"/#{@team.subdomain}"}>{@team.name}</.a>
      </li>
      <li :for={item <- @item}>
        <.icon name="hero-chevron-right-micro" class="breadcrumb-separator size-4" />
        <%= if Map.get(item, :path) do %>
          <.a kind={:custom} navigate={item.path}>{item.label}</.a>
        <% else %>
          <span aria-current="page">{item.label}</span>
        <% end %>
      </li>
    </ol>
    """
  end
end
