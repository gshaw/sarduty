defmodule Web.Admin.OrganizationNewLive do
  use Web, :live_view_app_layout

  alias App.Model.Organization
  alias App.Repo

  # A new organization (#512). The rest is in its own space: a SAR Duty admin adds its
  # organization admins next, then its teams from its Teams page.
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "New organization")
      |> assign_form(Organization.build_new_changeset())

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Organizations" path={~p"/admin/orgs"} />
      <:item label="New organization" />
    </.breadcrumbs>
    <h1 class="title">New organization</h1>

    <.form for={@form} id="organization-form" phx-change="validate" phx-submit="save" class="measure">
      <.error_summary form={@form} />
      <.input field={@form[:name]} label="Name">
        In full, as on the back of the ID card: "BC Search and Rescue Association".
      </.input>
      <.input field={@form[:short_name]} label="Short name">
        Beside the logo in the bar: "BCSARA".
      </.input>
      <.input field={@form[:slug]} label="Slug">
        Its pages: {Web.Endpoint.host()}/orgs/{@form[:slug].value || "slug"}. It cannot be
        changed later.
      </.input>
      <.input
        field={@form[:timezone]}
        type="combobox"
        label="Time zone"
        prompt="Select a time zone"
        options={Organization.timezone_options()}
      />
      <.form_actions>
        <.button variant={:success}>Create organization</.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"organization" => params}, socket) do
    changeset = params |> Organization.build_new_changeset() |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"organization" => params}, socket) do
    case params |> Organization.build_new_changeset() |> Repo.insert() do
      {:ok, organization} ->
        socket =
          socket
          |> put_flash(:info, "Created #{organization.short_name}. Add its organization admins.")
          |> push_navigate(to: ~p"/orgs/#{organization}/settings/admins")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))
end
