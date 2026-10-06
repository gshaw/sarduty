defmodule Web.Components.AdminTabs do
  use Web, :function_component

  import Web.Components.A

  attr :current, :atom, required: true, values: [:teams, :organizations, :admins]

  # The admin section's pages, under the Admin link in the top bar.
  def admin_tabs(assigns) do
    ~H"""
    <nav class="tabs" aria-label="Admin">
      <.a kind={:custom} navigate={~p"/admin"} aria-current={@current == :teams && "page"}>
        Teams
      </.a>
      <.a
        kind={:custom}
        navigate={~p"/admin/orgs"}
        aria-current={@current == :organizations && "page"}
      >
        Organizations
      </.a>
      <.a kind={:custom} navigate={~p"/admin/admins"} aria-current={@current == :admins && "page"}>
        Admins
      </.a>
    </nav>
    """
  end
end
