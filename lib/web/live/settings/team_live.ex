defmodule Web.Settings.TeamLive do
  use Web, :live_view_app_layout

  import Web.Components.OpenInMaps
  import Web.Components.PersonHead
  import Web.Components.OrgLogo
  import Web.Components.TeamSettingsTabs

  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Repo

  # Settings' General tab (#153), an overview of the team like a record page (#1076): the
  # team on top, its details and organization, and its records and Actions beside them.
  # Change team edits the names and address, which letters and forms print (#995);
  # Change logo sets the logo (#1075); Change team contacts picks who Get help lists
  # (#780); Change access key replaces the key (#727). The team comes from the URL,
  # /teams/:subdomain/settings.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      socket
      |> assign(page_title: "Team settings")
      |> assign(organization: team |> Repo.preload(:organization) |> Map.get(:organization))
      |> assign(has_logo: Team.logo_file(team.subdomain) != nil)
      |> assign(key_level: if(!D4H.records?(team), do: Team.key_level(team)))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:general} />

    <.person_head
      id="team-head"
      class="team-head mb-6"
      name={@current_team.name}
    >
      <:picture>
        <img
          :if={@has_logo}
          id="team-logo"
          src={Web.TeamController.logo_url(@current_team, :fit)}
          class="team-head-logo"
          alt="Team logo"
        />
        <span :if={!@has_logo} id="team-initials" class="team-head-logo is-initials">
          {Web.Navigation.team_initials(@current_team.name)}
        </span>
      </:picture>
    </.person_head>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content team={@current_team} key_level={@key_level} />
      </aside>
      <main class="content-2/3">
        <.main_content
          team={@current_team}
          organization={@organization}
          maps_app={@current_user.maps_app}
        />
      </main>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :organization, :map, default: nil
  attr :maps_app, :string, required: true

  defp main_content(assigns) do
    ~H"""
    <dl id="team-details">
      <dt>Legal name</dt>
      <dd id="team-legal-name">{@team.legal_name}</dd>
      <dt>Abbreviated name</dt>
      <dd id="team-abbreviated-name">{@team.abbreviated_name}</dd>
      <dt>Mailing address</dt>
      <dd id="team-mailing-address">
        <%= if present?(@team.mailing_address) do %>
          <span class="whitespace-pre-line">{@team.mailing_address}</span>
          <span :if={city_line(@team) != ""} class="block">{city_line(@team)}</span>
        <% else %>
          <span class="hint">None yet</span>
        <% end %>
      </dd>
      <dt>Place</dt>
      <dd id="team-place">
        <%= if @team.lat && @team.lng do %>
          {Service.Format.coordinate({@team.lat, @team.lng}, 5)}
          <.open_in_maps
            id="team-maps"
            app={@maps_app}
            coordinate={"#{@team.lat},#{@team.lng}"}
            label={@team.name}
          />
        <% else %>
          <span class="hint">Not known yet</span>
        <% end %>
      </dd>
      <dt>Time zone</dt>
      <dd id="team-timezone">{@team.timezone}</dd>
    </dl>
    <%!-- A team in an organization (#512). --%>
    <dl :if={@organization} id="team-organization">
      <dt>Organization</dt>
      <dd id="settings-organization">
        <div class="media mt-2">
          <.org_logo
            id="settings-organization-logo"
            src={@organization.logo_at && Web.OrganizationController.logo_url(@organization)}
            name={@organization.name}
          />
          {@organization.name}
        </div>
      </dd>
    </dl>
    """
  end

  attr :team, :map, required: true
  attr :key_level, :string, default: nil

  # Where the records come from and whose key reads them, beside the action that changes
  # the key, then the rest of Actions.
  defp sidebar_content(assigns) do
    ~H"""
    <dl id="team-source">
      <dt>Records</dt>
      <dd id="team-records">
        {records_text(@team)}
        <span :if={key_text(@team, @key_level)} class="hint block">
          {key_text(@team, @key_level)}
        </span>
      </dd>
    </dl>
    <dl id="team-actions-section">
      <dt>Actions</dt>
      <dd>
        <ul id="team-actions" class="action-list">
          <li>
            <.a id="team-edit" navigate={~p"/teams/#{@team}/settings/edit"}>Change team</.a>
          </li>
          <li>
            <.a id="team-logo-change" navigate={~p"/teams/#{@team}/settings/logo"}>Change logo</.a>
          </li>
          <li>
            <.a
              id="team-contacts-change"
              navigate={~p"/teams/#{@team}/settings/contacts"}
            >Change team contacts</.a>
          </li>
          <li :if={!App.Model.DemoTeam.demo?(@team)}>
            <.a
              id="team-key-change"
              navigate={~p"/teams/#{@team}/settings/access-key"}
            >Change access key</.a>
          </li>
          <li :if={!D4H.records?(@team)}>
            <.a
              id="team-d4h"
              external={true}
              href={D4H.build_url(@team, "/dashboard")}
            >Open in {D4H.service_name(@team)}</.a>
          </li>
        </ul>
      </dd>
    </dl>
    """
  end

  defp present?(text), do: is_binary(text) and String.trim(text) != ""

  # "Cedar Creek BC V5K 0A1", under the address.
  defp city_line(team),
    do: [team.city, team.postal_code] |> Enum.filter(&present?/1) |> Enum.join(" ")

  # "D4H, team 4210 in Canada", or "SAR Duty Records", which has one team per key.
  defp records_text(team) do
    if D4H.records?(team) do
      D4H.service_name(team)
    else
      region =
        Enum.find_value(D4H.regions(), fn {name, host} -> host == team.d4h_api_host && name end)

      team_text = "team #{team.d4h_team_id}"
      "#{D4H.service_name(team)}, #{if region, do: "#{team_text} in #{region}", else: team_text}"
    end
  end

  # "Alex Chen's key, an Owner in D4H." A Records key needs no owner.
  defp key_text(team, key_level) do
    if !D4H.records?(team) do
      if text = Team.key_text(team, key_level), do: "#{text}."
    end
  end
end
