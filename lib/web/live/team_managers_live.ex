defmodule Web.TeamManagersLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  import Web.Components.TeamManagers

  alias App.Accounts
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.OrganizationAdmin
  alias App.Model.TeamLoginGrant
  alias App.Repo

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    managers = Member.get_managers(team, DateTime.utc_now())
    login_emails = managers |> Enum.map(& &1.email) |> Accounts.login_emails()

    organization = team |> Repo.preload(:organization) |> Map.get(:organization)

    socket =
      assign(socket,
        page_title: "Team settings · Team admins",
        managers: managers,
        grants: TeamLoginGrant.get_for_team(team),
        login_emails: login_emails,
        organization: organization,
        organization_admins: organization_admins(organization),
        sar_duty_admins: Enum.sort(Accounts.admin_emails())
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:managers} />
    <p :if={!D4H.records?(@current_team)} class="max-w-3xl">
      These people can log in to SAR Duty for {@current_team.name}. They are the members with
      Owner or Editor access in {@service}. Members who are retired or have left cannot log in.
      To add or remove someone, change their access in {@service}. SAR Duty follows within 10 minutes.
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

    <section :if={@organization} id="organization-admins" class="mt-8 max-w-3xl">
      <h2 class="heading">{@organization.short_name}'s organization admins</h2>
      <p>
        They keep {@organization.name}'s settings and hours tags, and can turn your ID cards on or
        off. They see your team's totals, never its members.
      </p>
      <p :if={@organization_admins == []} class="hint">None yet.</p>
      <ul :if={@organization_admins != []} id="organization-admin-emails">
        <li :for={email <- @organization_admins} class="break-all">{email}</li>
      </ul>
    </section>

    <section id="sar-duty-admins" class="mt-8 max-w-3xl">
      <h2 class="heading">SAR Duty admins</h2>
      <p>
        They run SAR Duty and can open every team. Reach them at <.a href="mailto:support@sarduty.com">support@sarduty.com</.a>.
      </p>
      <ul id="sar-duty-admin-emails">
        <li :for={email <- @sar_duty_admins} class="break-all">{email}</li>
      </ul>
    </section>
    """
  end

  defp organization_admins(nil), do: []

  defp organization_admins(organization),
    do: organization |> OrganizationAdmin.get_for_organization() |> Enum.map(& &1.email)
end
