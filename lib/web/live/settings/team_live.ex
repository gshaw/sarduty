defmodule Web.Settings.TeamLive do
  use Web, :live_view_app_layout

  import Web.Components.FileDrop
  import Web.Components.TeamSettingsTabs

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.Team
  alias App.Operation.SaveTeamSignature
  alias App.Operation.UpdateTeamSettings
  alias App.Repo

  # The team comes from the URL, /teams/:subdomain/settings (#153).
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      socket
      |> assign(page_title: "Team settings")
      |> assign(organization: team |> Repo.preload(:organization) |> Map.get(:organization))
      |> assign_form(Team.build_settings_changeset(team))
      |> assign(watch_groups: watch_groups(team))
      |> assign(signature_error: nil)
      |> allow_upload(:signature,
        accept: ~w(.png .jpg .jpeg),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    {:ok, socket}
  end

  # A watched group D4H dropped stays chosen, named as gone, so saving other settings
  # never switches the check to all members quietly (#366).
  defp watch_groups(team) do
    groups = team.id |> Group.get_all() |> Enum.map(&{&1.title, &1.d4h_group_id})

    case team.watch_d4h_group_id do
      nil ->
        groups

      id ->
        if List.keymember?(groups, id, 1),
          do: groups,
          else: [{"A deleted group", id} | groups]
    end
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:general} />
    <div class="measure">
      <%!-- The tabs list the other settings. MCP tokens shows there only once a SAR Duty
      admin turns it on, and ID cards are on Endorsements, so say how to get them. A team
      in an organization (#512) says who its organization admins are. --%>
      <ul
        :if={@organization != nil or !@current_team.id_cards_enabled or !@current_team.mcp_enabled}
        class="row-links mb-4"
      >
        <li :if={@organization} id="settings-organization" class="py-2">
          <div class="media">
            <img
              :if={@organization.logo}
              src={Web.OrganizationController.logo_url(@organization)}
              width="32"
              height="32"
              class="size-8 rounded"
              alt=""
            />
            <div>
              {@organization.name}
              <span class="hint block">
                Its organization admins set your hours tags and can turn your ID cards on or
                off.
                <.a navigate={~p"/teams/#{@current_team}/settings/managers"}>See who they are</.a>
              </span>
            </div>
          </div>
        </li>
        <li :if={!@current_team.id_cards_enabled} id="settings-cards-off" class="py-2">
          ID cards
          <span :if={!@organization} class="hint block">
            Members carry them in Apple Wallet or Google Wallet. A SAR Duty admin turns them
            on once they have checked your team.
          </span>
          <span :if={@organization} class="hint block">
            Members carry them in Apple Wallet or Google Wallet. {@organization.short_name}'s
            organization admins or a SAR Duty admin turn them on.
          </span>
        </li>
        <li :if={!@current_team.mcp_enabled} id="settings-mcp-off" class="py-2">
          MCP tokens
          <span class="hint block">
            Let your AI agent read the team's data. A trial, so ask a SAR Duty admin
            to turn it on for your team.
          </span>
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
        <.file_drop
          id="team-signature"
          upload={@uploads.signature}
          label="Signer's signature (optional)"
          kinds="a PNG or JPEG"
          errors={if @signature_error, do: [@signature_error], else: []}
        >
          A PNG or JPEG of the signature, on white or transparent. New tax credit letters
          print it above the signer's name. Letters already made keep theirs.
          <:current :if={@current_team.signature}>
            <div class="flex flex-wrap items-center gap-4">
              <img
                id="signature-preview"
                src={Web.ImageData.png_data_url(@current_team.signature)}
                class="h-16 max-w-xs border border-border-subtle bg-paper p-1"
                alt="The signer's signature"
              />
              <.button
                id="remove-signature"
                type="button"
                phx-click="remove_signature"
                data-confirm="Remove the signature? New tax credit letters go out unsigned until you add one."
              >
                Remove signature
              </.button>
            </div>
          </:current>
        </.file_drop>
        <.input
          field={@form[:not_seen_days]}
          type="select"
          label="Members who have not attended"
          options={Team.not_seen_days_kinds()}
        >
          Needs attention lists the members you watch who have not attended an activity in
          this long, so someone can check in with them.
        </.input>
        <.input
          field={@form[:watch_d4h_group_id]}
          type="select"
          label="Watch"
          options={[{"All members", ""} | @watch_groups]}
        >
          All current members, or one group. For anything more, such as Callout without a
          subgroup, make a group with group rules.
        </.input>
        <fieldset id="watch-standings">
          <legend>Standing</legend>
          <.hint>Watch members with these standings.</.hint>
          <input type="hidden" name="form[watch_standings][]" value="" />
          <label :for={{label, value} <- Team.watch_standing_kinds()} class="choice">
            <input
              type="checkbox"
              id={"watch-standing-#{value}"}
              name="form[watch_standings][]"
              value={value}
              checked={value in (@form[:watch_standings].value || [])}
            />
            {label}
          </label>
          <.error :for={{message, _opts} <- @form[:watch_standings].errors}>{message}</.error>
        </fieldset>
        <.input
          field={@form[:new_d4h_access_key]}
          label={D4H.key_name(@current_team)}
          type="password"
          autocomplete="off"
        >
          <%= if D4H.records?(@current_team) do %>
            SAR Duty uses this one key to read and change your team's records in SAR Duty Records.
          <% else %>
            SAR Duty uses this one key for every D4H request: the nightly refresh, attendance,
            mileage, photos, and group changes.
          <% end %>
          <span id="team-key-status">{key_status(@current_team)}</span>
        </.input>
        <div :if={D4H.records?(@current_team)} id="team-key-owner" class="mb-4 text-sm">
          <p :if={@current_team.d4h_access_key_owner}>
            The key is named <strong>{@current_team.d4h_access_key_owner}</strong>
            in SAR Duty Records.
          </p>
          <p class="action">
            <.a
              id="records-keys"
              external={true}
              href={"https://#{D4H.records_host()}/teams/#{@current_team.subdomain}/keys"}
            >Create a key in SAR Duty Records</.a>
          </p>
        </div>
        <div :if={!D4H.records?(@current_team)} id="team-key-owner" class="mb-4 text-sm">
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
            >create a D4H access key</.a>.
          </p>
        </div>
        <.form_actions>
          <.button variant={:success}>Save settings</.button>
          <:trailing>
            <.button type="button" phx-click="refresh">
              Refresh
            </.button>
          </:trailing>
        </.form_actions>
      </.form>
    </div>
    """
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "form"))
  end

  defp key_status(%Team{d4h_access_key: nil} = team) do
    "SAR Duty cannot reach #{D4H.service_name(team)} for this team. Save a #{D4H.key_name(team)}."
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

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :signature, ref)}

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
    team = socket.assigns.current_team
    # A team with no place on its record keeps the one it has.
    {lat, lng} = d4h_team.coordinate || {team.lat, team.lng}

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
          |> put_flash(:info, "Team refreshed.")

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
end
