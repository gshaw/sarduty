defmodule Web.MeFieldsLive do
  use Web, {:live_view_app_layout, access: :member, view_events: ["validate"]}

  import Web.Components.CustomFields
  import Web.Components.OrgLogo
  import Web.MemberLogin

  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Operation.SaveOwnDetails
  alias App.Repo

  # Change fields (#1056), /teams/:subdomain/me/fields: the member fields D4H lets a member
  # see (#681), the team's own, then its organization's, each under its name and logo, as
  # Team settings' Fields tab lists them. Each keeps D4H's order: the ones D4H sets to
  # `editable` are inputs, saved straight to D4H, and the `viewable` ones show their value
  # in place. A key that can't fill in fields shows them all as values. A team admin
  # viewing as the member (#425) sees the page with saving turned off.
  def mount(_params, _session, socket) do
    member = socket.assigns.current_member
    team = member.team |> Repo.preload(:organization)
    editable = SaveOwnDetails.fields(member)
    editable_ids = MapSet.new(editable, & &1.id)
    {organization, own} = team.id |> CustomField.member_fields(:self) |> split()

    socket =
      assign(socket,
        page_title: "Change fields",
        team: team,
        editable?: editable != [],
        read_only:
          own
          |> Enum.concat(organization)
          |> Enum.map(& &1.id)
          |> Enum.reject(&MapSet.member?(editable_ids, &1)),
        own_fields: own,
        organization_fields: organization,
        values: member.custom_values || %{}
      )

    {:ok, socket}
  end

  defp split(fields), do: Enum.split_with(fields, &CustomField.organisation?/1)

  # Keeps what was typed when the page renders again, such as after D4H refuses.
  def handle_event("validate", params, socket),
    do: {:noreply, keep_values(socket, params)}

  def handle_event("save", params, socket) do
    socket = keep_values(socket, params)
    values = %{"fields" => params["fields"] || %{}}

    {:noreply,
     with_login(socket, fn member ->
       case SaveOwnDetails.call(member, socket.assigns.current_user, values, DateTime.utc_now()) do
         {:ok, _result} ->
           socket
           |> put_flash(:info, "Your fields are saved.")
           |> push_navigate(to: ~p"/teams/#{member.team}/me")

         {:error, text} ->
           put_flash(socket, :error, text)
       end
     end)}
  end

  defp keep_values(socket, params),
    do: update(socket, :values, &Map.merge(&1, params["fields"] || %{}))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@team}/me"} />
      <:item label="Change fields" />
    </.breadcrumbs>
    <div class="measure">
      <h1 class="title">Change fields</h1>
      <p class="lead">Changes go to your team's records, where your team admins see them.</p>
      <.form for={%{}} as={:fields} id="fields-form" phx-change="validate" phx-submit="save">
        <section :if={@own_fields != []} id="team-fields">
          <h2 class="heading media">
            <.org_logo id="team-fields-logo" src={team_logo(@team)} name={@team.name} />
            {@team.name}
          </h2>
          <.custom_field_inputs
            fields={@own_fields}
            values={@values}
            read_only={@read_only}
            timezone={@team.timezone}
            bundle_tag="h3"
          />
        </section>
        <section
          :if={@organization_fields != []}
          id="organization-fields"
          class={@own_fields != [] && "mt-8"}
        >
          <h2 class="heading media">
            <.org_logo
              id="organization-fields-logo"
              src={organization_logo(@team.organization)}
              name={organization_name(@team)}
            />
            {organization_name(@team)}
          </h2>
          <.custom_field_inputs
            fields={@organization_fields}
            values={@values}
            read_only={@read_only}
            timezone={@team.timezone}
            bundle_tag="h3"
          />
        </section>
        <.form_actions :if={@editable?}>
          <.button variant={:success} phx-disable-with="Saving…" disabled={@viewing_as != nil}>
            Save fields
          </.button>
          <.button navigate={~p"/teams/#{@team}/me"}>Cancel</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  defp team_logo(team),
    do: Team.logo_file(team.subdomain) && Web.TeamController.logo_url(team, :square)

  defp organization_logo(%{logo_at: %DateTime{}} = organization),
    do: Web.OrganizationController.logo_url(organization)

  defp organization_logo(_organization), do: nil

  defp organization_name(team), do: Team.organization_name(team) || "Your organization"
end
