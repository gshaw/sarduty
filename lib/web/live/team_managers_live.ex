defmodule Web.TeamManagersLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamManagers

  alias App.Accounts
  alias App.Model.Member
  alias App.Model.TeamLoginGrant

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    managers = Member.get_managers(team, DateTime.utc_now())
    login_emails = managers |> Enum.map(& &1.email) |> Accounts.login_emails()

    socket =
      assign(socket,
        page_title: "Managers",
        managers: managers,
        grants: TeamLoginGrant.get_for_team(team),
        login_emails: login_emails
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team} />
    <h1 class="title mb-p">{@page_title}</h1>
    <p class="max-w-3xl">
      These people can log in to SAR Duty for {@current_team.name}: everyone D4H makes an
      Owner or Editor who is not retired and has not left, as of the last refresh. To add or
      remove someone, change their access in D4H. SAR Duty follows after the next refresh.
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
