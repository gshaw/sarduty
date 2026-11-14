defmodule Web.Settings.FieldLive do
  use Web, :live_view_app_layout

  import Web.Components.FieldDefinitions

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Operation.ChangeCustomField
  alias App.Operation.DeleteCustomField
  alias App.Repo

  # One custom field on its own page, /teams/:subdomain/settings/fields/:id (#872): what
  # it means, its type, who added it and when, and every choice. The Fields tab lists the
  # team's fields and links here. A team's own field, when the key can change fields
  # (#1056 step 4), gets its actions under the title: Change field, then Delete field or
  # Archive field, or Restore field alone when archived. Change field's form only saves.
  def mount(%{"id" => id}, _session, socket) do
    team = Repo.preload(socket.assigns.current_team, :organization)
    field = CustomField.get_for_team!(team.id, id)

    socket
    |> assign(
      page_title: field.title,
      changes: CustomField.team_changes?(team, field),
      team_names: %{team.d4h_team_id => team.name},
      organization_name: team.organization && team.organization.short_name
    )
    |> assign_field(field)
    |> then(&{:ok, &1})
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
    <h1 class="title">{@field.title}</h1>
    <p :if={@field.archived_at} id="field-archived" class="lead">This field is archived.</p>
    <.page_actions :if={@changes and @field.archived_at} id="field-actions">
      <:action>
        <.a id="field-restore" href="#" phx-click="restore" phx-disable-with="Restoring…">Restore field</.a>
      </:action>
    </.page_actions>
    <.page_actions :if={@changes and !@field.archived_at} id="field-actions">
      <:action>
        <.a
          id="field-change"
          navigate={~p"/teams/#{@current_team}/settings/fields/#{@field.id}/edit"}
        >Change field</.a>
      </:action>
      <:action :if={@deletable}>
        <.a
          id="field-delete"
          href="#"
          phx-click="delete"
          phx-disable-with="Deleting…"
          {Web.DeleteConfirm.field(@current_team, @field)}
        >Delete field</.a>
      </:action>
      <:action :if={!@deletable}>
        <.a id="field-archive" href="#" phx-click="archive" phx-disable-with="Archiving…">Archive field</.a>
      </:action>
    </.page_actions>
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

  def handle_event("archive", _params, socket), do: set_archived(socket, true)
  def handle_event("restore", _params, socket), do: set_archived(socket, false)

  def handle_event("delete", _params, socket) do
    %{current_team: team, current_user: user, field: field} = socket.assigns

    case DeleteCustomField.call(team, user, field, DateTime.utc_now()) do
      :ok ->
        socket
        |> put_flash(:info, "Deleted the #{field.title} field.")
        |> push_navigate(to: ~p"/teams/#{team}/settings/fields?kind=#{field.target}")
        |> then(&{:noreply, &1})

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp set_archived(socket, archived?) do
    %{current_team: team, current_user: user, field: field} = socket.assigns

    case ChangeCustomField.set_archived(team, user, field, archived?, DateTime.utc_now()) do
      :ok ->
        socket
        |> put_flash(
          :info,
          "#{if archived?, do: "Archived", else: "Restored"} the #{field.title} field."
        )
        |> assign_field(CustomField.get_for_team!(team.id, field.id))
        |> then(&{:noreply, &1})

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  # Delete field only while nobody has answered it; Archive field once someone has, as
  # DeleteCustomField allows. Counted only for a field the team changes.
  defp assign_field(socket, field) do
    deletable =
      socket.assigns.changes and is_nil(field.archived_at) and
        field |> CustomField.answer_count() |> DeleteCustomField.check_answers() == :ok

    assign(socket, field: field, deletable: deletable)
  end

  defp restricted_text(%{target: "member"}),
    do:
      "On a member field, restricted changes nothing in SAR Duty. Team admins see every member's answer, as for any member field."

  defp restricted_text(%{target: "equipment"}),
    do: "Only team admins see its values, as for any equipment field."

  defp restricted_text(_field),
    do: "Only team admins see its values. Members and your organization never do."
end
