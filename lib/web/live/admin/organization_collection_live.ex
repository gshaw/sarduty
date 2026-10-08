defmodule Web.Admin.OrganizationCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.AdminTabs

  alias App.Model.Organization
  alias App.Repo

  def mount(_params, _session, socket) do
    organizations = Organization.get_all() |> Repo.preload(:teams)
    {:ok, assign(socket, page_title: "Organizations", organizations: organizations)}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">Admin</h1>
    <.admin_tabs current={:organizations} />
    <div class="heading-row">
      <h2 class="heading">Organizations</h2>
      <.button navigate={~p"/admin/orgs/new"} variant={:success} size={:sm}>
        New organization
      </.button>
    </div>
    <.empty_state :if={@organizations == []} id="no-organizations" title="No organizations yet">
      Add one with New organization.
    </.empty_state>
    <.table
      :if={@organizations != []}
      id="organizations"
      rows={@organizations}
      row_id={&"organization-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={organization} label="Organization">
        <div class="media">
          <img
            :if={organization.logo}
            src={Web.OrganizationController.logo_url(organization)}
            width="32"
            height="32"
            class="size-8 rounded"
            alt=""
          />
          <div>
            <.a navigate={~p"/admin/orgs/#{organization.id}"}>{organization.name}</.a>
            <.hint>{organization.short_name} · /orgs/{organization.slug}</.hint>
          </div>
        </div>
      </:col>
      <:col :let={organization} label="Teams">
        {organization.teams |> Enum.map(& &1.name) |> Enum.sort() |> Enum.join(", ")}
      </:col>
    </.table>
    """
  end
end
