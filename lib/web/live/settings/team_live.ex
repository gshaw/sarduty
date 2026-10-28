defmodule Web.Settings.TeamLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Operation.RefreshTeamDetails
  alias App.Operation.UpdateTeamSettings
  alias App.Repo

  # Settings' General tab (#153): the team itself, from D4H, and the key SAR Duty uses.
  # The team comes from the URL, /teams/:subdomain/settings.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      socket
      |> assign(page_title: "Team settings")
      |> assign(organization: team |> Repo.preload(:organization) |> Map.get(:organization))
      |> assign_form(Team.build_settings_changeset(team))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:general} />
    <div class="measure">
      <%!-- ID cards are on Endorsements, so say how to get them while they're off. A team in
      an organization (#512) says who its organization admins are. --%>
      <ul
        :if={@organization != nil or !@current_team.id_cards_enabled}
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
                <.a navigate={~p"/teams/#{@current_team}/settings/team-admins"}>See who they are</.a>
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
      </ul>

      <.form for={@form} id="team_settings_form" phx-submit="save" phx-change="validate">
        <.error_summary form={@form} />
        <.input field={@form[:name]} label="Name" />
        <div class="grid grid-cols-2 gap-x-6">
          <.input field={@form[:lat]} readonly label="Latitude" />
          <.input field={@form[:lng]} readonly label="Longitude" />
        </div>
        <.input field={@form[:timezone]} label="Time zone" readonly>
          The place and time zone come from {@service}. Refresh copies them and the name
          again.
        </.input>
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
          <.button variant={:success} phx-disable-with="Saving…">Save settings</.button>
          <:trailing>
            <.button type="button" phx-click="refresh" phx-disable-with="Refreshing…">
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
    %{current_team: team, current_user: user} = socket.assigns

    case UpdateTeamSettings.call(team, form_params, user) do
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
    case RefreshTeamDetails.call(socket.assigns.current_team) do
      {:ok, team} ->
        socket =
          socket
          |> assign(current_team: team)
          |> assign_form(Team.build_settings_changeset(team))
          |> put_flash(:info, "Team refreshed.")

        {:noreply, socket}

      {:error, text} when is_binary(text) ->
        {:noreply, put_flash(socket, :error, text)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end
end
