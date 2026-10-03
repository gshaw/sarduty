defmodule Web.Admin.OrganizationLive do
  use Web, :live_view_app_layout

  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.SaveOrganization

  def mount(params, _session, socket) do
    organization =
      if id = params["id"], do: Organization.get!(id), else: %Organization{}

    socket =
      socket
      |> assign(page_title: organization.name || "New Organization")
      |> assign(organization: organization, teams: Team.get_all() |> Enum.sort_by(& &1.name))
      |> assign(team_ids: if(organization.id, do: Organization.team_ids(organization), else: []))
      |> assign_form(Organization.build_changeset(organization))
      |> allow_upload(:logo, accept: ~w(.png .jpg .jpeg), max_entries: 1)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <p>
      <.a navigate={~p"/admin/organizations"}>← Organizations</.a>
    </p>
    <h1 class="title">{@organization.name || "New organization"}</h1>

    <.form
      for={@form}
      id="organization-form"
      phx-change="validate"
      phx-submit="save"
      class="max-w-xl"
    >
      <.input field={@form[:name]} label="Name">
        In full, as on the back of the pass: "BC Search and Rescue Association".
      </.input>
      <.input field={@form[:short_name]} label="Short name">
        Beside the logo in the verify site's bar: "BCSARA".
      </.input>
      <.input field={@form[:slug]} label="Slug">
        Its start page on the verify site: {Web.VerifyHost.host()}/o/{@form[:slug].value || "slug"}.
      </.input>
      <.input field={@form[:website]} label="Website" placeholder="https://" />

      <div class="mb-p">
        <label for={@uploads.logo.ref} class="block font-semibold">Logo</label>
        <div class="my-2 flex items-center gap-p">
          <img
            :if={@organization.logo}
            id="organization-logo"
            src={Web.OrganizationController.logo_url(@organization)}
            class="size-16 rounded border border-hr"
            alt=""
          />
          <.live_file_input upload={@uploads.logo} />
        </div>
        <.hint>
          PNG or JPEG, square or wide. Stands in for a member team's logo when D4H has none.
        </.hint>
        <p :for={error <- upload_errors(@uploads.logo)} class="text-danger-1">
          {upload_error(error)}
        </p>
        <p :for={{message, _opts} <- @form[:logo].errors} class="text-danger-1">{message}</p>
      </div>

      <fieldset id="organization-teams" class="mb-p">
        <legend class="font-semibold">Member teams</legend>
        <.hint>Their passes are rebuilt when you save, and phones update in a minute or so.</.hint>
        <input type="hidden" name="team_ids[]" value="" />
        <label :for={team <- @teams} class="flex items-center gap-2 my-1">
          <input
            type="checkbox"
            name="team_ids[]"
            value={team.id}
            checked={team.id in @team_ids}
          />
          {team.name}
          <span
            :if={team.organization_id && team.organization_id != @organization.id}
            class="text-sm text-warning-1"
          >
            (in another organization)
          </span>
        </label>
      </fieldset>

      <.form_actions>
        <.button variant={:success}>Save</.button>
      </.form_actions>
    </.form>

    <section :if={@organization.id} id="organization-host" class="mt-p2 max-w-xl text-sm">
      <h2 class="heading">Their own verify address</h2>
      <p>
        Until then, cards link to {Web.VerifyHost.host()} and show the organization's name and
        logo. When they want {own_host(@organization)}, they add this DNS record. Then we add
        the certificate and deploy, as in docs/organizations.md.
      </p>
      <pre class="p-p rounded bg-base-2 overflow-x-auto">{own_host(@organization)}  CNAME  {Web.VerifyHost.host()}</pre>
    </section>
    """
  end

  def handle_event("validate", params, socket) do
    changeset =
      socket.assigns.organization
      |> Organization.build_changeset(params["organization"] || %{})
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign_form(changeset) |> assign(team_ids: team_ids(params, socket))}
  end

  def handle_event("save", params, socket) do
    logo =
      case consume_uploaded_entries(socket, :logo, fn %{path: path}, _entry ->
             {:ok, File.read!(path)}
           end) do
        [bytes] -> bytes
        [] -> nil
      end

    organization = socket.assigns.organization
    form_params = params["organization"] || %{}

    case SaveOrganization.call(organization, form_params, logo, team_ids(params, socket)) do
      {:ok, organization} ->
        socket =
          socket
          |> put_flash(:info, "Saved #{organization.name}.")
          |> push_navigate(to: ~p"/admin/organizations/#{organization.id}")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, socket |> assign_form(changeset) |> assign(team_ids: team_ids(params, socket))}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  # Only ids of teams on the page, so a crafted form can't name anything else.
  defp team_ids(params, socket) do
    known = Map.new(socket.assigns.teams, &{Integer.to_string(&1.id), &1.id})
    params |> Map.get("team_ids", []) |> Enum.flat_map(&List.wrap(known[&1]))
  end

  # verify.<their domain>, from the website, or a placeholder until it has one.
  defp own_host(%Organization{website: website}) when is_binary(website) do
    host = URI.parse(website).host || ""
    "verify." <> String.replace_prefix(host, "www.", "")
  end

  defp own_host(_organization), do: "verify.example.org"

  defp upload_error(:too_large), do: "That file is too large."
  defp upload_error(:not_accepted), do: "Use a PNG or JPEG."
  defp upload_error(:too_many_files), do: "Pick one file."
  defp upload_error(_error), do: "That file didn't upload."
end
