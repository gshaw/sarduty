defmodule Web.Org.TeamNewLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Team
  alias App.Operation.SetTeamOrganization
  alias App.Repo

  # Add a team to the organization (#512), for SAR Duty admins only: it is when they
  # check a team is real. Only teams in no organization are offered, and the team is
  # looked up again among them on save, never taken from the client.
  def mount(_params, _session, socket) do
    unless socket.assigns.current_user.is_admin, do: raise(Web.Status.NotFound)

    socket =
      socket
      |> assign(page_title: "Add a team", teams: addable_teams())
      |> assign_form(%{}, [])

    {:ok, socket}
  end

  defp addable_teams do
    Team |> where([t], is_nil(t.organization_id)) |> order_by([t], asc: t.name) |> Repo.all()
  end

  defp assign_form(socket, params, errors),
    do: assign(socket, form: to_form(params, as: "team", errors: errors))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Teams" path={~p"/orgs/#{@current_organization}"} />
      <:item label="Add a team" />
    </.breadcrumbs>
    <h1 class="title">Add a team to {@current_organization.short_name}</h1>

    <div class="measure">
      <.form for={@form} id="add-team-form" phx-submit="add">
        <.input
          field={@form[:team_id]}
          type="combobox"
          label="Team"
          prompt="Select a team"
          options={Enum.map(@teams, &{&1.name, &1.id})}
        >
          Teams in no organization, A to Z. A new team signs up first. A team in another
          organization is removed there first.
        </.input>

        <.warning_text class="mb-6">
          Add only a team you have checked is real. {@current_organization.short_name}'s
          organization admins can then turn on its ID cards.
        </.warning_text>

        <h2 class="heading">What changes</h2>
        <ul id="add-team-changes" class="mb-6 list-disc pl-6">
          <li>The back of its ID cards names {@current_organization.name}.</li>
          <li :for={line <- hours_lines(@current_organization)}>{line}</li>
          <li>
            {@current_organization.short_name}'s organization admins can turn its ID cards on or
            off, and see its totals, never its members.
          </li>
          <li>Its team admins get an email.</li>
        </ul>

        <.form_actions>
          <.button variant={:success} phx-disable-with="Adding…">Add team</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  defp hours_lines(organization) do
    tags = Activity.organization_hours_tags(organization)

    for kind <- [:primary, :secondary, :other] do
      if tag = tags[kind],
        do: "Its tax credit letters count #{tag} as #{Activity.hours_kind_name(kind)}.",
        else: "It keeps its own tag for #{Activity.hours_kind_name(kind)}."
    end
  end

  def handle_event("add", %{"team" => %{"team_id" => team_id}}, socket) do
    %{current_organization: organization, current_user: user} = socket.assigns
    team = Enum.find(addable_teams(), &(Integer.to_string(&1.id) == team_id))

    result =
      if team,
        do: SetTeamOrganization.call(team, organization, user),
        else: {:error, :not_listed}

    case result do
      {:ok, team} ->
        socket =
          socket
          |> put_flash(:info, "Added #{team.name} to #{organization.short_name}.")
          |> push_navigate(to: ~p"/orgs/#{organization}/teams/#{team}")

        {:noreply, socket}

      {:error, {:hours_tag, text}} ->
        {:noreply, assign_form(socket, %{"team_id" => team_id}, team_id: {text, []})}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(teams: addable_teams())
         |> assign_form(%{"team_id" => team_id},
           team_id: {"Select a team in no organization.", []}
         )}
    end
  end
end
