defmodule Web.Org.SettingsLive do
  use Web, :live_view_app_layout

  import Web.Components.CopyButton
  import Web.Components.FileDrop
  import Web.Components.OrgSettingsTabs

  alias App.Model.Organization
  alias App.Operation.SaveOrganization

  # Organization settings › General (#512): its name, time zone, and logo. The slug
  # cannot change: its verify page and logo URL use it.
  def mount(_params, _session, socket) do
    organization = socket.assigns.current_organization

    socket =
      socket
      |> assign(page_title: "Organization settings")
      |> assign_form(Organization.build_changeset(organization))
      |> allow_upload(:logo, accept: ~w(.png .jpg .jpeg), max_entries: 1)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.org_settings_tabs organization={@current_organization} current={:general} />
    <.form for={@form} id="organization-form" phx-change="validate" phx-submit="save" class="measure">
      <.error_summary form={@form} />
      <.input field={@form[:name]} label="Name">
        In full, as on the back of the ID card: "BC Search and Rescue Association".
      </.input>
      <.input field={@form[:short_name]} label="Short name">
        Beside the logo on the verify page: "BCSARA".
      </.input>
      <.input field={@form[:website]} label="Website" placeholder="https://" />
      <.input
        field={@form[:timezone]}
        type="combobox"
        label="Time zone"
        prompt="Select a time zone"
        options={Organization.timezone_options()}
      >
        For dates about the organization. Each team's dates use its own time zone.
      </.input>

      <.file_drop
        id="organization-logo-file"
        upload={@uploads.logo}
        label="Logo"
        kinds="a PNG or JPEG"
        errors={for {message, _opts} <- @form[:logo].errors, do: message}
      >
        PNG or JPEG, square or wide. Shown on its verify page, never on a team's ID card.
        <:current :if={@current_organization.logo}>
          <img
            id="organization-logo"
            src={Web.OrganizationController.logo_url(@current_organization)}
            class="size-16 rounded border border-border-subtle"
            alt=""
          />
        </:current>
      </.file_drop>

      <.form_actions>
        <.button variant={:success}>Save settings</.button>
      </.form_actions>
    </.form>

    <section id="organization-verify-page" class="mt-8 measure">
      <h2 class="heading">Verify page</h2>
      <p>
        Its own page to verify ID cards, with its logo and name. Its slug cannot be
        changed.
      </p>
      <.copy_code_block
        id="organization-verify-url"
        value={"#{Web.VerifyHost.host()}/orgs/#{@current_organization.slug}"}
        label="Copy address"
      />
    </section>
    """
  end

  def handle_event("validate", params, socket) do
    changeset =
      socket.assigns.current_organization
      |> Organization.build_changeset(params["organization"] || %{})
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :logo, ref)}

  def handle_event("save", params, socket) do
    logo =
      case consume_uploaded_entries(socket, :logo, fn %{path: path}, _entry ->
             {:ok, File.read!(path)}
           end) do
        [bytes] -> bytes
        [] -> nil
      end

    organization = socket.assigns.current_organization

    case SaveOrganization.call(organization, params["organization"] || %{}, logo) do
      {:ok, organization} ->
        socket =
          socket
          |> assign(current_organization: organization)
          |> assign_form(Organization.build_changeset(organization))
          |> put_flash(:info, "Settings saved.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))
end
