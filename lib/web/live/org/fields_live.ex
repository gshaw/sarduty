defmodule Web.Org.FieldsLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.FieldDefinitions
  import Web.Components.OrgSettingsTabs

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Repo

  # Organization settings › Fields (#872): the organization's own custom fields, laid out
  # as on a team's Fields page and read from its teams' copies. D4H gives every team its
  # organization's fields, so there's no column of teams; a choice a team added to one
  # names the team. Never a value: a RESTRICTED field shows only what it is.
  def mount(_params, _session, socket) do
    organization = socket.assigns.current_organization

    teams =
      Team |> where([t], t.organization_id == ^organization.id) |> order_by(:id) |> Repo.all()

    {archived, live} =
      teams
      |> Enum.map(& &1.id)
      |> CustomField.get_all_organisation()
      |> CustomField.merge_copies()
      |> Enum.split_with(& &1.archived_at)

    socket =
      assign(socket,
        page_title: "Organization settings · Fields",
        teams: teams,
        team_names: Map.new(teams, &{&1.d4h_team_id, &1.name}),
        by_target: CustomField.by_target(live),
        archived: CustomField.by_target(archived)
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.org_settings_tabs organization={@current_organization} current={:fields} />
    <div class="measure">
      <p class="lead">
        The fields {@current_organization.short_name} added to its teams' records. Every team
        gets them, so its reports and forms can read them on any team.
      </p>
      <p :if={@teams != []}>Change them in {D4H.service_name(hd(@teams))}.</p>
    </div>

    <.empty_state :if={@teams == []} id="no-teams" title="No teams yet" class="mt-8">
      The fields come from its teams. A SAR Duty site admin adds them.
    </.empty_state>
    <.empty_state
      :if={@teams != [] and @by_target == []}
      id="no-fields"
      title="No fields yet"
      class="mt-8"
    >
      {@current_organization.short_name} has added no fields to its teams' records.
    </.empty_state>

    <section :for={{target, fields} <- @by_target} id={"fields-#{target}"} class="mt-12">
      <h2 class="heading">{CustomField.target_title(target)}</h2>
      <p class="hint mb-4">
        {Service.Format.count(length(fields), one: "%d field.", many: "%d fields.")}
      </p>
      <.field_definitions
        id={"fields-#{target}-list"}
        fields={fields}
        team_names={@team_names}
        organization_name={@current_organization.short_name}
        timezone={@current_organization.timezone}
        from?={false}
        publish?={target in ~w(incident exercise event)}
        restricted_text="Only its teams' admins see its values."
      />
    </section>

    <details :if={@archived != []} id="archived-fields" class="mt-12">
      <summary class="heading">
        Archived fields · {@archived |> Enum.flat_map(&elem(&1, 1)) |> length()}
      </summary>
      <section :for={{target, fields} <- @archived} id={"archived-#{target}"} class="mt-6">
        <h3 class="subheading mb-2">{CustomField.target_title(target)}</h3>
        <.field_definitions
          id={"archived-#{target}-list"}
          fields={fields}
          team_names={@team_names}
          organization_name={@current_organization.short_name}
          timezone={@current_organization.timezone}
          from?={false}
        />
      </section>
    </details>
    """
  end
end
