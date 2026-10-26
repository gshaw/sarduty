defmodule Web.Components.Breadcrumbs do
  use Web, :function_component

  import Web.Components.A

  slot :item do
    attr :label, :string
    attr :path, :string
  end

  # Where a record's page sits under its section: the section first, then each level, the
  # last being the page you're on. The bar names the team, so the trail leaves it out
  # (#312). A section's own page has no trail: with nothing to go back to, it renders
  # nothing.
  def breadcrumbs(assigns) do
    ~H"""
    <ol :if={Enum.any?(@item, &Map.get(&1, :path))} class="breadcrumbs">
      <li :for={{item, i} <- Enum.with_index(@item)}>
        <.icon :if={i > 0} name="chevron-right" size={:sm} class="breadcrumb-separator" />
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
