defmodule Web.Components.Breadcrumbs do
  use Web, :function_component

  import Web.Components.A

  attr :team, :any, default: nil

  slot :item do
    attr :label, :string
    attr :path, :string
  end

  def breadcrumbs(assigns) do
    ~H"""
    <div class="mb-p05 text-sm">
      <.a :if={@team} navigate={~p"/#{@team.subdomain}"}>{@team.name}</.a>
      <span :for={item <- @item}>
        /
        <%= if Map.get(item, :path) do %>
          <.a navigate={item.path}>{item.label}</.a>
        <% else %>
          {item.label}
        <% end %>
      </span>
    </div>
    """
  end
end
