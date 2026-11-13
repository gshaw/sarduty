defmodule Web.Settings.FieldLive do
  use Web, :live_view_app_layout

  import Web.Components.FieldDefinitions

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Operation.ChangeCustomField
  alias App.Repo

  # One custom field on its own page, /teams/:subdomain/settings/fields/:id (#872): what
  # it means, its type, who added it and when, and every choice. The Fields tab lists the
  # team's fields and links here. A team's own field gets Change field, or Restore field
  # when archived, when the key can change fields (#1056 step 4).
  def mount(%{"id" => id}, _session, socket) do
    team = Repo.preload(socket.assigns.current_team, :organization)
    field = CustomField.get_for_team!(team.id, id)

    socket =
      assign(socket,
        page_title: field.title,
        field: field,
        changes: CustomField.team_changes?(team, field),
        team_names: %{team.d4h_team_id => team.name},
        organization_name: team.organization && team.organization.short_name
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Team settings" path={~p"/teams/#{@current_team}/settings"} />
      <:item
        label="Fields"
        path={~p"/teams/#{@current_team}/settings/fields?kind=#{@field.target}"}
      />
      <:item label={@field.title} />
    </.breadcrumbs>
    <.heading_row>
      <h1 class="title">{@field.title}</h1>
      <:action :if={@changes}>
        <.button
          :if={!@field.archived_at}
          id="field-change"
          navigate={~p"/teams/#{@current_team}/settings/fields/#{@field.id}/edit"}
        >
          Change field
        </.button>
        <.button
          :if={@field.archived_at}
          id="field-restore"
          phx-click="restore"
          phx-disable-with="Restoring…"
        >
          Restore field
        </.button>
      </:action>
    </.heading_row>
    <p :if={@field.archived_at} id="field-archived" class="lead">This field is archived.</p>
    <.field_details
      field={@field}
      timezone={@current_team.timezone}
      team_names={@team_names}
      organization_name={@organization_name}
      team_name={@current_team.name}
      service={D4H.service_name(@current_team)}
      restricted_text={restricted_text(@field)}
      changes={@changes}
    />
    """
  end

  def handle_event("restore", _params, socket) do
    %{current_team: team, current_user: user, field: field} = socket.assigns

    case ChangeCustomField.set_archived(team, user, field, false, DateTime.utc_now()) do
      :ok ->
        socket
        |> put_flash(:info, "Restored the #{field.title} field.")
        |> assign(field: CustomField.get_for_team!(team.id, field.id))
        |> then(&{:noreply, &1})

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp restricted_text(%{target: "member"}),
    do:
      "On a member field, restricted changes nothing in SAR Duty. Team admins see every member's answer, as for any member field."

  defp restricted_text(%{target: "equipment"}),
    do: "Only team admins see its values, as for any equipment field."

  defp restricted_text(_field),
    do: "Only team admins see its values. Members and your organization never do."
end
