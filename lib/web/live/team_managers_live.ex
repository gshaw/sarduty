defmodule Web.TeamManagersLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamManagers

  alias App.Accounts
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.TeamLoginGrant

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    managers = Member.get_managers(team, DateTime.utc_now())
    login_emails = managers |> Enum.map(& &1.email) |> Accounts.login_emails()

    socket =
      assign(socket,
        page_title: "Team admins",
        managers: managers,
        grants: TeamLoginGrant.get_for_team(team),
        login_emails: login_emails
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Team settings" path={~p"/teams/#{@current_team}/settings"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>
    <p :if={!D4H.records?(@current_team)} class="max-w-3xl">
      These people can log in to SAR Duty for {@current_team.name}. They are the members D4H
      makes an Owner or Editor. Members who are retired or have left cannot log in. To add or
      remove someone, change their access in D4H. SAR Duty follows within 10 minutes.
    </p>
    <p :if={D4H.records?(@current_team)} class="max-w-3xl">
      These people can log in to SAR Duty for {@current_team.name}. They are the members who
      are team admins. Members who are retired or have left cannot log in. To add or remove
      someone, change Team admin on their Change details page.
    </p>
    <.team_managers
      id="team-managers"
      managers={@managers}
      grants={@grants}
      login_emails={@login_emails}
    />
    """
  end
end
