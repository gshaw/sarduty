defmodule Web.Settings.FieldsLive do
  use Web, :live_view_app_layout

  import Web.Components.FieldDefinitions
  import Web.Components.TeamSettingsTabs

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Operation.SaveTeamMemberFields
  alias App.Repo

  # Settings' Fields tab, /teams/:subdomain/settings/fields (#872): every custom field on
  # the team's records, by what it's on and then by D4H's bundles, with what D4H says
  # about each. Read only, except which member fields SAR Duty copies (#681), which only
  # changes SAR Duty's own setting. Archived fields wait, closed, at the foot.
  def mount(_params, _session, socket) do
    team = Repo.preload(socket.assigns.current_team, :organization)

    socket =
      socket
      |> assign(page_title: "Team settings · Fields", service: D4H.service_name(team))
      |> assign(
        team_names: %{team.d4h_team_id => team.name},
        organization_name: team.organization && team.organization.short_name
      )
      |> assign_fields(team)

    {:ok, socket}
  end

  defp assign_fields(socket, team) do
    {archived, live} =
      team.id |> CustomField.get_all_with_archived() |> Enum.split_with(& &1.archived_at)

    assign(socket,
      by_target: CustomField.by_target(live),
      archived: CustomField.by_target(archived)
    )
  end

  def handle_event("save_member_fields", params, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    ids = params |> Map.get("fields", []) |> Enum.reject(&(&1 == ""))
    :ok = SaveTeamMemberFields.call(team, ids, user)

    socket =
      socket
      |> assign_fields(team)
      |> put_flash(:info, "Member fields saved.")

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:fields} />
    <div class="measure">
      <p class="lead">
        The fields on your team's records, from your team and your organization. Reports,
        forms, and agents read them by title.
      </p>
      <p>Change them in {@service}. SAR Duty refreshes them every 10 minutes.</p>
    </div>

    <.empty_state :if={@by_target == []} id="no-fields" title="No fields yet" class="mt-8">
      Your team and organization have added no fields to records.
    </.empty_state>

    <section :for={{target, fields} <- @by_target} id={"fields-#{target}"} class="mt-12">
      <h2 class="heading">{CustomField.target_title(target)}</h2>
      <p class="hint mb-4">
        {Service.Format.count(length(fields), one: "%d field.", many: "%d fields.")}
      </p>
      <%= if target == "member" do %>
        <p class="measure mb-4">
          SAR Duty copies only the member fields you check. Team admins see them, and each
          member sees their own when the field allows it. Restricted fields stay private.
        </p>
        <form id="member-fields-form" phx-submit="save_member_fields">
          <input type="hidden" name="fields[]" value="" />
          <.field_definitions
            id="fields-member-list"
            fields={fields}
            team_names={@team_names}
            organization_name={@organization_name}
            timezone={@current_team.timezone}
            copy?
          />
          <.form_actions>
            <.button variant={:success} phx-disable-with="Saving…">Save member fields</.button>
          </.form_actions>
        </form>
      <% else %>
        <.field_definitions
          id={"fields-#{target}-list"}
          fields={fields}
          team_names={@team_names}
          organization_name={@organization_name}
          timezone={@current_team.timezone}
          publish?={target in ~w(incident exercise event)}
          restricted_text="Only team admins see its values."
        />
      <% end %>
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
          organization_name={@organization_name}
          timezone={@current_team.timezone}
        />
      </section>
    </details>
    """
  end
end
