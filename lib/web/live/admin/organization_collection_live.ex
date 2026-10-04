defmodule Web.Admin.OrganizationCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.Organization
  alias App.Repo

  def mount(_params, _session, socket) do
    organizations = Organization.get_all() |> Repo.preload(:teams)
    {:ok, assign(socket, page_title: "Organizations", organizations: organizations)}
  end

  def render(assigns) do
    ~H"""
    <p>
      <.a navigate={~p"/admin"}>← Admin</.a>
    </p>
    <div class="mb-p flex flex-wrap items-center justify-between gap-p">
      <h1 class="title mb-0">Organizations</h1>
      <.button navigate={~p"/admin/organizations/new"} variant={:success} size={:sm}>
        New organization
      </.button>
    </div>
    <p :if={@organizations == []} id="no-organizations">No organizations yet.</p>
    <.table
      :if={@organizations != []}
      id="organizations"
      rows={@organizations}
      row_id={&"organization-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={organization} label="Organization">
        <div class="flex items-center gap-2">
          <img
            :if={organization.logo}
            src={Web.OrganizationController.logo_url(organization)}
            width="32"
            height="32"
            class="size-8 shrink-0 rounded"
            alt=""
          />
          <div>
            <.a navigate={~p"/admin/organizations/#{organization.id}"}>{organization.name}</.a>
            <.hint>{organization.short_name} · /o/{organization.slug}</.hint>
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
