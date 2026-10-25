defmodule Web.Admin.OrganizationCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.Organization
  alias App.Model.OrganizationAdmin
  alias App.Repo

  # Every organization, with who outside SAR Duty can reach it (#512). Each opens in its
  # own space, where a SAR Duty admin adds its teams and organization admins.
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Organizations",
        organizations: Organization.get_all() |> Repo.preload(:teams),
        admins: OrganizationAdmin.get_all_by_organization(),
        now: DateTime.utc_now()
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">Organizations</h1>
      <:action>
        <.button navigate={~p"/admin/orgs/new"} variant={:success}>
          New organization
        </.button>
      </:action>
    </.heading_row>
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
            <.a navigate={~p"/orgs/#{organization}"}>{organization.name}</.a>
            <.hint>{organization.short_name} · /orgs/{organization.slug}</.hint>
          </div>
        </div>
      </:col>
      <:col :let={organization} label="Teams" class="max-md:hidden">
        <span id={"organization-#{organization.id}-teams"}>
          {Service.Format.count(length(organization.teams), one: "%d team", many: "%d teams")}
        </span>
      </:col>
      <:col :let={organization} label="Organization admins">
        <span
          :if={Map.get(@admins, organization.id, []) == []}
          id={"organization-#{organization.id}-no-admins"}
          class="text-danger-text"
        >
          None
        </span>
        <ul :if={Map.get(@admins, organization.id, []) != []}>
          <li
            :for={admin <- @admins[organization.id]}
            class="flex items-baseline gap-2 md:whitespace-nowrap"
          >
            <span>{admin.email}</span>
            <span class="hint ml-auto pl-4">
              {Service.Format.days_ago(admin.last_seen_at, @now, organization.timezone) || "Never"}
            </span>
          </li>
        </ul>
      </:col>
    </.table>
    <p :if={@organizations != []} class="hint mt-4">
      Add or remove an organization's admins on its Organization admins tab.
    </p>
    """
  end
end
