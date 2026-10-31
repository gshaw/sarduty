defmodule Web.Settings.TeamLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.Team
  alias App.Operation.RefreshTeamDetails
  alias App.Operation.UpdateTeamSettings
  alias App.Repo

  # Settings' General tab (#153): the team itself, from D4H. The key SAR Duty uses is on
  # Access key (#727). The team comes from the URL, /teams/:subdomain/settings.
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
            Members carry them in Apple Wallet or Google Wallet. A SAR Duty site admin turns them
            on once they have checked your team.
          </span>
          <span :if={@organization} class="hint block">
            Members carry them in Apple Wallet or Google Wallet. {@organization.short_name}'s
            organization admins or a SAR Duty site admin turn them on.
          </span>
        </li>
      </ul>

      <.form for={@form} id="team_settings_form" phx-submit="save" phx-change="validate">
        <.error_summary form={@form} />
        <%!-- Three names for the room each place has (#738). --%>
        <p id="team-names-lead">
          Your team has three names, one for each amount of room. Each starts as your team's
          name.
        </p>
        <.input field={@form[:name]} label="Name">
          Used on most pages, emails, ID cards, and the phone top bar. {Service.Format.characters(
            Team.name_advice(:name)
          )} or fewer fits everywhere.
        </.input>
        <.input field={@form[:legal_name]} label="Legal name">
          In full, as registered. Used on tax credit letters, the page that checks them, and
          the back of ID cards.
        </.input>
        <.input field={@form[:abbreviated_name]} label="Abbreviated name">
          Starts texts to members, where room is tight. {Service.Format.characters(
            Team.name_advice(:abbreviated_name)
          )} or fewer.
        </.input>
        <div class="grid grid-cols-2 gap-x-6">
          <.input field={@form[:lat]} readonly label="Latitude" />
          <.input field={@form[:lng]} readonly label="Longitude" />
        </div>
        <.input field={@form[:timezone]} label="Time zone" readonly>
          The place and time zone come from {@service}. Refresh copies them again.
        </.input>
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

  def handle_event("validate", %{"form" => form_params}, socket) do
    changeset = Team.build_settings_changeset(socket.assigns.current_team, form_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"form" => form_params}, socket) do
    case UpdateTeamSettings.call(socket.assigns.current_team, form_params) do
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
