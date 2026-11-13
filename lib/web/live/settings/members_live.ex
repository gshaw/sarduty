defmodule Web.Settings.MembersLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.Group
  alias App.Model.Team
  alias App.Operation.SaveTeamMemberSettings

  # Settings' Members tab, /teams/:subdomain/settings/members: the Retiring group (#514)
  # and the attendance check (#366), the two settings that decide which members SAR Duty
  # counts and watches.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      socket
      |> assign(page_title: "Team settings · Members")
      |> assign_choices(team)
      |> assign_form(Team.build_members_changeset(team))

    {:ok, socket}
  end

  # A group D4H dropped stays chosen, named as gone, so saving the other setting never
  # changes it quietly (#366).
  defp assign_choices(socket, team) do
    all = team.id |> Group.get_all() |> Enum.map(&{&1.title, &1.d4h_group_id})

    retiring =
      team |> SaveTeamMemberSettings.retiring_choices() |> Enum.map(&{&1.title, &1.d4h_group_id})

    assign(socket,
      watch_groups: with_saved(all, team.watch_d4h_group_id),
      retiring_groups: with_saved(retiring, team.retiring_d4h_group_id)
    )
  end

  defp with_saved(groups, nil), do: groups

  defp with_saved(groups, id) do
    if List.keymember?(groups, id, 1), do: groups, else: [{"A deleted group", id} | groups]
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))

  def handle_event("validate", %{"form" => params}, socket) do
    changeset = Team.build_members_changeset(socket.assigns.current_team, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case SaveTeamMemberSettings.call(socket.assigns.current_team, params) do
      {:ok, team} ->
        socket =
          socket
          |> assign(current_team: team)
          |> assign_choices(team)
          |> assign_form(Team.build_members_changeset(team))
          |> put_flash(:info, "Team settings saved.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:members} />
    <div class="measure">
      <p class="lead">Which members SAR Duty counts, and who Needs attention watches.</p>
      <.form for={@form} id="member-settings-form" phx-submit="save" phx-change="validate">
        <.error_summary form={@form} />
        <.input
          field={@form[:retiring_d4h_group_id]}
          type="select"
          label="Retiring group"
          options={[{"None", ""} | @retiring_groups]}
        >
          Members of this group are retiring. SAR Duty leaves them out of counts, invites,
          reminders, and Take attendance until they are retired. Only groups without group
          rules are listed.
        </.input>

        <h2 class="heading mt-8">Attendance check</h2>
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
          <label :for={{label, value} <- Team.watch_standing_kinds(@current_team)} class="choice">
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
        <.form_actions>
          <.button variant={:success} phx-disable-with="Saving…">Save settings</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end
end
