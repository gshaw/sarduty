defmodule Web.Settings.FieldsLive do
  use Web, :live_view_app_layout

  import Web.Components.FieldDefinitions
  import Web.Components.StatSwitch
  import Web.Components.TeamSettingsTabs

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Operation.SaveTeamMemberFields

  # Settings' Fields tab, /teams/:subdomain/settings/fields (#872): an index of the custom
  # fields on the team's records, one kind at a time (`?kind=member`), each field a line
  # that opens its own page, Web.Settings.FieldLive. Read only, except which member
  # fields SAR Duty copies (#681), which only changes SAR Duty's own setting. A kind's
  # archived fields wait, closed, at its foot.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      socket
      |> assign(page_title: "Team settings · Fields", service: D4H.service_name(team))
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
    assigns =
      assign(assigns,
        fields: Map.get(assigns.live, assigns.kind, []),
        archived_fields: Map.get(assigns.archived, assigns.kind, []),
        path: &~p"/teams/#{assigns.current_team}/settings/fields/#{&1.id}"
      )

    ~H"""
    <.team_settings_tabs team={@current_team} current={:fields} />
    <div class="measure">
      <p class="lead">
        The fields on your team's records, from your team and your organization. Reports,
        forms, and agents read them by title.
      </p>
      <p>Change them in {@service}. SAR Duty refreshes them every 10 minutes.</p>
    </div>

    <.empty_state :if={@counts == []} id="no-fields" title="No fields yet" class="mt-8">
      Your team and organization have added no fields to records.
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

    <section :if={@kind} id={"fields-#{@kind}"} class="mt-6">
      <%= if @kind == "member" do %>
        <p class="measure mb-4">
          SAR Duty copies only the member fields you check. Team admins see them, and each
          member sees their own when the field allows it. Restricted fields stay private.
        </p>
        <form :if={@fields != []} id="member-fields-form" phx-submit="save_member_fields">
          <input type="hidden" name="fields[]" value="" />
          <.field_list id="fields-member-list" fields={@fields} path={@path} copy? />
          <.form_actions>
            <.button variant={:success} phx-disable-with="Saving…">Save member fields</.button>
          </.form_actions>
        </form>
      <% else %>
        <.field_list
          id={"fields-#{@kind}-list"}
          fields={@fields}
          path={@path}
          publish?={@kind in ~w(incident exercise event)}
        />
      <% end %>

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
