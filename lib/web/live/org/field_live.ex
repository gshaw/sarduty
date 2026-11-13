defmodule Web.Org.FieldLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.FieldDefinitions

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Repo

  # One of an organization's custom fields on its own page,
  # /orgs/:slug/settings/fields/:id (#872), as on a team's: its teams' copies folded into
  # one, so a choice a team added names the team. The id is one team's copy. Never a
  # value.
  def mount(%{"id" => id}, _session, socket) do
    organization = socket.assigns.current_organization

    teams =
      Team |> where([t], t.organization_id == ^organization.id) |> order_by(:id) |> Repo.all()

    field = teams |> Enum.map(& &1.id) |> CustomField.get_organisation!(id)

    socket =
      assign(socket,
        page_title: field.title,
        field: field,
        teams: teams,
        team_names: Map.new(teams, &{&1.d4h_team_id, &1.name})
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Organization settings" path={~p"/orgs/#{@current_organization}/settings"} />
      <:item
        label="Fields"
        path={~p"/orgs/#{@current_organization}/settings/fields?kind=#{@field.target}"}
      />
      <:item label={@field.title} />
    </.breadcrumbs>
    <h1 class="title">{@field.title}</h1>
    <p :if={@field.archived_at} id="field-archived" class="lead">This field is archived.</p>
    <.field_details
      field={@field}
      timezone={@current_organization.timezone}
      team_names={@team_names}
      organization_name={@current_organization.short_name}
      service={D4H.service_name(hd(@teams))}
      restricted_text={restricted_text(@field)}
    />
    """
  end

  defp restricted_text(%{target: "member"}),
    do:
      "On a member field, restricted changes nothing. Its teams' admins see every member's answer."

  defp restricted_text(_field), do: "Only its teams' admins see its values."
end
