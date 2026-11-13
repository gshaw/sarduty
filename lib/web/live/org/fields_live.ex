defmodule Web.Org.FieldsLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.FieldDefinitions
  import Web.Components.OrgSettingsTabs
  import Web.Components.StatSwitch

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Repo
  alias Web.Settings.FieldsLive

  # Organization settings › Fields (#872): an index of the organization's own custom
  # fields, one kind at a time, read from its teams' copies, as on a team's Fields tab.
  # Each opens its own page, Web.Org.FieldLive. Never a value.
  def mount(_params, _session, socket) do
    organization = socket.assigns.current_organization

    teams =
      Team |> where([t], t.organization_id == ^organization.id) |> order_by(:id) |> Repo.all()

    fields =
      teams
      |> Enum.map(& &1.id)
      |> CustomField.get_all_organisation()
      |> CustomField.merge_copies()

    {archived, live} = Enum.split_with(fields, & &1.archived_at)

    socket =
      assign(socket,
        page_title: "Organization settings · Fields",
        teams: teams,
        counts: CustomField.counts_by_target(fields),
        live: Enum.group_by(live, & &1.target),
        archived: Enum.group_by(archived, & &1.target)
      )

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :kind, FieldsLive.kind(params["kind"], socket.assigns.counts))}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        fields: Map.get(assigns.live, assigns.kind, []),
        archived_fields: Map.get(assigns.archived, assigns.kind, []),
        path: &~p"/orgs/#{assigns.current_organization}/settings/fields/#{&1.id}"
      )

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
      :if={@teams != [] and @counts == []}
      id="no-fields"
      title="No fields yet"
      class="mt-8"
    >
      {@current_organization.short_name} has added no fields to its teams' records.
    </.empty_state>

    <div :if={@counts != []} class="mt-8">
      <.stat_switch label="Fields">
        <:view
          :for={{target, count} <- @counts}
          id={"fields-kind-#{target}"}
          patch={~p"/orgs/#{@current_organization}/settings/fields?kind=#{target}"}
          current={@kind == target}
          count={count}
        >
          {CustomField.target_title(target)}
        </:view>
      </.stat_switch>
    </div>

    <section :if={@kind} id={"fields-#{@kind}"} class="mt-6">
      <.field_list id={"fields-#{@kind}-list"} fields={@fields} path={@path} />
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
