defmodule Web.Settings.FieldLive do
  use Web, :live_view_app_layout

  import Web.Components.FieldDefinitions

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Repo

  # One custom field on its own page, /teams/:subdomain/settings/fields/:id (#872): what
  # it means, its type, who added it and when, and every choice. Read only. The Fields
  # tab lists the team's fields and links here.
  def mount(%{"id" => id}, _session, socket) do
    team = Repo.preload(socket.assigns.current_team, :organization)
    field = CustomField.get_for_team!(team.id, id)

    socket =
      assign(socket,
        page_title: field.title,
        field: field,
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
    <h1 class="title">{@field.title}</h1>
    <p :if={@field.archived_at} id="field-archived" class="lead">This field is archived.</p>
    <.field_details
      field={@field}
      timezone={@current_team.timezone}
      team_names={@team_names}
      organization_name={@organization_name}
      team_name={@current_team.name}
      service={D4H.service_name(@current_team)}
      restricted_text={restricted_text(@field)}
    />
    """
  end

  defp restricted_text(%{target: "member"}),
    do:
      "On a member field, restricted changes nothing in SAR Duty. Team admins see every member's answer, as for any member field."

  defp restricted_text(%{target: "equipment"}),
    do: "Only team admins see its values, as for any equipment field."

  defp restricted_text(_field),
    do: "Only team admins see its values. Members and your organization never do."
end
