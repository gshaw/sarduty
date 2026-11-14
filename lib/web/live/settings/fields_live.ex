defmodule Web.Settings.FieldsLive do
  use Web, :live_view_app_layout

  import Web.Components.FieldDefinitions
  import Web.Components.StatSwitch
  import Web.Components.TeamSettingsTabs

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Repo

  # Settings' Fields tab, /teams/:subdomain/settings/fields (#872): an index of the custom
  # fields on the team's records, one kind at a time (`?kind=member`), each field a row
  # link to its own page, Web.Settings.FieldLive: the team's own first, then its
  # organization's (#1056). A team admin adds the team's own fields here, with a key that
  # can (#1056 step 4); one that can't says why. A kind's archived fields wait, closed, at
  # its foot.
  def mount(_params, _session, socket) do
    team = Repo.preload(socket.assigns.current_team, :organization)

    socket =
      socket
      |> assign(
        page_title: "Team settings · Fields",
        service: D4H.service_name(team),
        can_change: Team.d4h_can?(team, :custom_fields),
        organization_name: team.organization && team.organization.short_name,
        # A logo beside each owner's heading, so its fields are told apart.
        team_logo: Team.logo_file(team.subdomain) && Web.TeamController.logo_url(team, :square),
        organization_logo:
          team.organization && team.organization.logo_at &&
            Web.OrganizationController.logo_url(team.organization)
      )
      |> assign_fields(team)

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :kind, kind(params["kind"], socket.assigns.counts))}
  end

  defp assign_fields(socket, team) do
    fields = CustomField.get_all_with_archived(team.id)
    {archived, live} = Enum.split_with(fields, & &1.archived_at)

    assign(socket,
      counts: CustomField.counts_by_target(fields),
      live: Enum.group_by(live, & &1.target),
      archived: Enum.group_by(archived, & &1.target)
    )
  end

  @doc "The kind to show: the one asked for, or the first with fields."
  def kind(asked, counts) do
    targets = Enum.map(counts, &elem(&1, 0))
    if asked in targets, do: asked, else: List.first(targets)
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        fields: Map.get(assigns.live, assigns.kind, []),
        archived_fields: Map.get(assigns.archived, assigns.kind, []),
        own_count:
          assigns.live
          |> Map.get(assigns.kind, [])
          |> Enum.count(&CustomField.team_changes?(assigns.current_team, &1)),
        path: &~p"/teams/#{assigns.current_team}/settings/fields/#{&1.id}"
      )

    ~H"""
    <.team_settings_tabs team={@current_team} current={:fields} />
    <.heading_row>
      <div class="measure">
        <p class="lead">
          The fields on your team's records, from your team and your organization. Reports,
          forms, and agents read them by title.
        </p>
        <p :if={@can_change} id="fields-who-changes">
          Add and change your team's own fields here.
          <span :if={@organization_name}>Only {@organization_name} can change its fields.</span>
        </p>
        <p :if={!@can_change} id="fields-key-cannot">
          Your team's access key cannot add or change fields, so change them in {@service}. To change them here, save a key from a {@service} Owner.
          <.a navigate={~p"/teams/#{@current_team}/settings/access-key"}>Change the access key</.a>
        </p>
      </div>
    </.heading_row>

    <.empty_state :if={@counts == []} id="no-fields" title="No fields yet" class="mt-8">
      Your team and organization have added no fields to records.
      <:action :if={@can_change}>
        <.button
          id="field-add"
          variant={:success}
          navigate={~p"/teams/#{@current_team}/settings/fields/new?kind=incident"}
        >
          Add field
        </.button>
      </:action>
    </.empty_state>

    <div :if={@counts != []} class="mt-8">
      <.stat_switch label="Fields">
        <:view
          :for={{target, count} <- @counts}
          id={"fields-kind-#{target}"}
          patch={~p"/teams/#{@current_team}/settings/fields?kind=#{target}"}
          current={@kind == target}
          count={count}
        >
          {CustomField.target_title(target)}
        </:view>
      </.stat_switch>
    </div>

    <%!-- A reader's width, so each row's chevron sits by its words. --%>
    <section :if={@kind} id={"fields-#{@kind}"} class="mt-6 max-w-3xl">
      <p :if={@kind == "member"} id="member-fields-who" class="measure mb-6">
        Team admins see every member's answers. A member sees their own when the field allows it.
      </p>
      <p :if={@kind == "team"} id="team-fields-who" class="measure mb-6">
        Facts about the team itself. Team admins fill them in on <.a navigate={
          ~p"/teams/#{@current_team}/settings"
        }>General</.a>.
      </p>
      <.field_list
        id={"fields-#{@kind}-list"}
        fields={@fields}
        path={@path}
        team_name={@current_team.name}
        organization_name={@organization_name}
        team_logo={@team_logo}
        organization_logo={@organization_logo}
      >
        <:team_action :if={@can_change}>
          <.button
            :if={@own_count > 1}
            id="field-order"
            navigate={~p"/teams/#{@current_team}/settings/fields/order?kind=#{@kind}"}
          >
            Change order
          </.button>
          <.button
            id="field-add"
            variant={:success}
            navigate={~p"/teams/#{@current_team}/settings/fields/new?kind=#{@kind}"}
          >
            Add field
          </.button>
        </:team_action>
      </.field_list>

      <details :if={@archived_fields != []} id="archived-fields" class="mt-8">
        <summary class="subheading">
          Archived · {length(@archived_fields)}
        </summary>
        <div class="mt-4">
          <.field_list id={"archived-#{@kind}-list"} fields={@archived_fields} path={@path} />
        </div>
      </details>
    </section>
    """
  end
end
