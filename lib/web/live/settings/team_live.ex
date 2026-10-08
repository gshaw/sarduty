defmodule Web.Settings.TeamLive do
  use Web, :live_view_narrow_layout

  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Operation.SaveTeamSignature
  alias App.Operation.UpdateTeamSettings

  # The team comes from the URL, /teams/:subdomain/settings (#153).
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      socket
      |> assign(page_title: "Team settings")
      |> assign_form(Team.build_settings_changeset(team))
      |> assign(signature_error: nil)
      |> allow_upload(:signature,
        accept: ~w(.png .jpg .jpeg),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.back_link navigate={~p"/teams/#{@current_team}"}>{@current_team.name}</.back_link>
      <h1 class="heading">Team settings</h1>
      <ul class="mb-4">
        <li>
          <.a id="settings-cards" navigate={~p"/teams/#{@current_team}/settings/cards"}>ID cards</.a>:
          qualifications on the back
        </li>
        <li>
          <.a id="settings-managers" navigate={~p"/teams/#{@current_team}/settings/managers"}>Team admins</.a>:
          who can log in
        </li>
        <li :if={@current_team.mcp_enabled}>
          <.a id="settings-mcp" navigate={~p"/teams/#{@current_team}/settings/mcp"}>MCP tokens</.a>:
          let your AI agent read the team's data
        </li>
        <li :if={!@current_team.mcp_enabled} id="settings-mcp-off">
          MCP tokens: let your AI agent read the team's data. A trial, so ask a SAR Duty admin
          to turn it on for your team.
        </li>
      </ul>

      <.form for={@form} id="team_settings_form" phx-submit="save" phx-change="validate">
        <.error_summary form={@form} />
        <.input field={@form[:name]} label="Name" />
        <div class="grid grid-cols-2 gap-x-6">
          <.input field={@form[:lat]} readonly label="Latitude" />
          <.input field={@form[:lng]} readonly label="Longitude" />
        </div>
        <.input field={@form[:timezone]} label="Time zone" readonly />
        <.input field={@form[:mailing_address]} label="Mailing address" type="textarea" rows="6" />
        <.input
          field={@form[:authorized_by_name]}
          label="Tax credit letters authorized by"
          type="textarea"
          rows="6"
        >
          The full name of your team president, or someone in a similar role. The CRA uses
          this during tax audits.
        </.input>
        <.input field={@form[:authorized_by_title]} label="Signer's title (optional)">
          Printed under the name on tax credit letters, like President.
        </.input>
        <div class="grid md:grid-cols-2 gap-x-6">
          <.input field={@form[:authorized_by_phone]} label="Signer's phone (optional)" />
          <.input
            field={@form[:authorized_by_email]}
            label="Signer's email (optional)"
            type="email"
          />
        </div>
        <div id="team-signature" class="mb-6">
          <.label for={@uploads.signature.ref}>Signer's signature (optional)</.label>
          <.hint>
            A PNG or JPEG of the signature, on white or transparent. New tax credit letters
            print it above the signer's name. Letters already made keep theirs.
          </.hint>
          <div :if={@current_team.signature} class="my-2 flex flex-wrap items-center gap-4">
            <img
              id="signature-preview"
              src={Web.ImageData.png_data_url(@current_team.signature)}
              class="h-16 max-w-xs border border-border-subtle bg-paper p-1"
              alt="The signer's signature"
            />
            <.button
              id="remove-signature"
              type="button"
              size={:sm}
              phx-click="remove_signature"
              data-confirm="Remove the signature? New tax credit letters go out unsigned until you add one."
            >
              Remove signature
            </.button>
          </div>
          <.live_file_input upload={@uploads.signature} class="my-2" />
          <.error :for={error <- upload_errors(@uploads.signature)}>{upload_error(error)}</.error>
          <.error :if={@signature_error} id="signature-error">{@signature_error}</.error>
        </div>
        <.input
          field={@form[:new_d4h_access_key]}
          label="D4H access key"
          type="password"
          autocomplete="off"
        >
          SAR Duty uses this one key for every D4H request: the nightly refresh, attendance,
          mileage, photos, and group changes.
          <span id="team-key-status">{key_status(@current_team)}</span>
        </.input>
        <div id="team-key-owner" class="mb-4 text-sm">
          <p :if={@current_team.d4h_access_key_owner}>
            The key belongs to the D4H member <strong>{@current_team.d4h_access_key_owner}</strong>.
          </p>
          <p
            :if={!Team.key_owner_is_sar_duty?(@current_team)}
            id="team-key-advice"
            class="callout"
          >
            Create the key from a D4H member named "SAR Duty" rather than a person. D4H history
            then shows SAR Duty for changes made here, and the key keeps working when people
            leave the team. In D4H, add a member named SAR Duty with Owner or Editor access. Log
            in as that member and <.a
              external={true}
              href="https://help.d4h.com/article/377-obtaining-an-api-access-key"
            >
              create a D4H access key
            </.a>.
          </p>
        </div>
        <.form_actions>
          <.button variant={:success}>Save settings</.button>
          <:trailing>
            <.button type="button" phx-click="refresh">Refresh from D4H</.button>
          </:trailing>
        </.form_actions>
      </.form>
    </div>
    """
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "form"))
  end

  defp key_status(%Team{d4h_access_key: nil}) do
    "SAR Duty cannot reach D4H for this team. Save a D4H access key."
  end

  defp key_status(%Team{d4h_access_key_saved_at: nil}) do
    "A key is saved. Leave blank to keep it."
  end

  defp key_status(%Team{} = team) do
    saved_on = Service.Format.date_long(team.d4h_access_key_saved_at, team.timezone)
    "Key saved #{saved_on}. Leave blank to keep it."
  end

  def handle_event("validate", %{"form" => form_params}, socket) do
    changeset = Team.build_settings_changeset(socket.assigns.current_team, form_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"form" => form_params}, socket) do
    signature = consume_signature(socket)

    with {:ok, team} <-
           UpdateTeamSettings.call(
             socket.assigns.current_team,
             form_params,
             socket.assigns.current_user
           ),
         {:ok, team} <- save_signature(team, signature) do
      socket =
        socket
        |> assign(current_team: team, signature_error: nil)
        |> assign_form(Team.build_settings_changeset(team))
        |> put_flash(:info, "Team settings saved.")

      {:noreply, socket}
    else
      {:error, :image} ->
        {:noreply, assign(socket, signature_error: "Use a PNG or JPEG image of the signature.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("remove_signature", _params, socket) do
    {:ok, team} = SaveTeamSignature.call(socket.assigns.current_team, nil)

    socket =
      socket
      |> assign(current_team: team)
      |> put_flash(:info, "Signature removed.")

    {:noreply, socket}
  end

  def handle_event("refresh", _params, socket) do
    d4h = D4H.build_context_from_team(socket.assigns.current_team)
    {:ok, d4h_team} = D4H.fetch_team(d4h)
    {lat, lng} = d4h_team.coordinate

    params = %{
      name: d4h_team.name,
      lat: lat,
      lng: lng,
      timezone: d4h_team.timezone
    }

    case Team.update(socket.assigns.current_team, params) do
      {:ok, team} ->
        socket =
          socket
          |> assign(current_team: team)
          |> assign_form(Team.build_settings_changeset(team))
          |> put_flash(:info, "Team refreshed from D4H.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp consume_signature(socket) do
    case consume_uploaded_entries(socket, :signature, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [bytes] -> bytes
      [] -> nil
    end
  end

  # No upload keeps the saved signature; only the remove button clears it.
  defp save_signature(team, nil), do: {:ok, team}
  defp save_signature(team, bytes), do: SaveTeamSignature.call(team, bytes)

  defp upload_error(:too_large), do: "That file is too large. Use one under 5 MB."
  defp upload_error(:not_accepted), do: "Use a PNG or JPEG."
  defp upload_error(:too_many_files), do: "Select one file."
  defp upload_error(_error), do: "That file did not upload. Try again."
end
