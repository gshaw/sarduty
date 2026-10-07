defmodule Web.Settings.TeamLive do
  use Web, :live_view_narrow_layout

  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Operation.UpdateTeamSettings

  # The team comes from the URL, /teams/:subdomain/settings (#153).
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      socket
      |> assign(page_title: "Team settings")
      |> assign_form(Team.build_settings_changeset(team))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <p>
        <.a navigate={~p"/teams/#{@current_team}"}>← {@current_team.name}</.a>
      </p>
      <h1 class="heading">Team settings</h1>
      <ul class="mb-p">
        <li>
          <.a id="settings-cards" navigate={~p"/teams/#{@current_team}/settings/cards"}>ID cards</.a>:
          qualifications on the back
        </li>
        <li>
          <.a id="settings-managers" navigate={~p"/teams/#{@current_team}/settings/managers"}>Managers</.a>:
          who can log in
        </li>
      </ul>

      <.form for={@form} id="team_settings_form" phx-submit="save" phx-change="validate">
        <.input field={@form[:name]} label="Name" />
        <div class="grid grid-cols-2 gap-hspacer">
          <.input field={@form[:lat]} readonly label="Latitude" class="bg-base-3" />
          <.input field={@form[:lng]} readonly label="Longitude" class="bg-base-3" />
        </div>
        <.input field={@form[:timezone]} label="Time zone" readonly class="bg-base-3" />
        <.input
          field={@form[:mailing_address]}
          label="Mailing address"
          type="textarea"
          class="h-[10rem]"
        />
        <.input
          field={@form[:authorized_by_name]}
          label="Tax credit letters authorized by"
          type="textarea"
          class="h-[10rem]"
        >
          Include the full name, title, address, and phone number of your team president, or
          someone in a similar role. The CRA uses this during tax audits.
        </.input>
        <.input
          field={@form[:new_d4h_access_key]}
          label="D4H access key (team)"
          type="password"
          autocomplete="off"
        >
          SAR Duty uses this one key for every D4H request: the nightly refresh, attendance,
          mileage, photos, and group changes.
          <span id="team-key-status">{key_status(@current_team)}</span>
        </.input>
        <div id="team-key-owner" class="mb-p text-sm">
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
            leave the team. In D4H, add a member named SAR Duty with Owner or Editor access,
            log in as it, and <.a
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
    case UpdateTeamSettings.call(
           socket.assigns.current_team,
           form_params,
           socket.assigns.current_user
         ) do
      {:ok, team} ->
        socket =
          socket
          |> assign(current_team: team)
          |> assign_form(Team.build_settings_changeset(team))
          |> put_flash(:info, "Team settings saved.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
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
end
