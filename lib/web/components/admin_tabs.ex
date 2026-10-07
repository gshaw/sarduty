defmodule Web.Components.AdminTabs do
  use Web, :function_component

  attr :current, :atom, required: true, values: [:teams, :organizations, :admins, :events, :mcp]

  # The admin section's pages, under the Admin link in the top bar.
  def admin_tabs(assigns) do
    ~H"""
    <.tabs label="Admin">
      <:tab navigate={~p"/admin"} current={@current == :teams}>Teams</:tab>
      <:tab navigate={~p"/admin/orgs"} current={@current == :organizations}>Organizations</:tab>
      <:tab navigate={~p"/admin/admins"} current={@current == :admins}>Admins</:tab>
      <:tab navigate={~p"/admin/events"} current={@current == :events}>Events</:tab>
      <:tab navigate={~p"/admin/mcp"} current={@current == :mcp}>MCP</:tab>
    </.tabs>
    """
  end
end
