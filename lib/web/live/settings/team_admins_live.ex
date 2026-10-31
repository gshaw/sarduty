defmodule Web.Settings.TeamAdminsLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  import Web.Components.TeamManagers

  alias App.Accounts
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.OrganizationAdmin
  alias App.Model.Team
  alias App.Model.TeamLoginGrant
  alias App.Operation.SaveTeamContacts
  alias App.Repo

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    managers = Member.get_managers(team, DateTime.utc_now())

    login_emails = managers |> Enum.map(& &1.email) |> Accounts.login_emails()

    organization = team |> Repo.preload(:organization) |> Map.get(:organization)
    now = DateTime.utc_now()

    socket =
      assign(socket,
        page_title: "Team settings · Team admins",
        managers: managers,
        grants: TeamLoginGrant.get_for_team(team),
        login_emails: login_emails,
        organization: organization,
        organization_admins: organization_admins(organization),
        sar_duty_admins: Enum.sort(Accounts.admin_emails()),
        contact_choices: SaveTeamContacts.choices(team, now)
      )

    {:ok, assign_saved_contacts(socket, team, now)}
  end

  defp assign_saved_contacts(socket, team, now) do
    changeset = team |> contacts_data(now) |> Team.build_contacts_changeset()
    assign_contacts_form(socket, changeset)
  end

  # The saved contacts that still count, so one who left shows as None.
  defp contacts_data(team, now) do
    case Member.get_team_contacts(team, now) do
      [] -> %{team | first_contact_id: nil, second_contact_id: nil}
      [first] -> %{team | first_contact_id: first.id, second_contact_id: nil}
      [first, second] -> %{team | first_contact_id: first.id, second_contact_id: second.id}
    end
  end

  defp assign_contacts_form(socket, changeset),
    do: assign(socket, contacts_form: to_form(changeset, as: "contacts"))

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:team_admins} />
    <p :if={!D4H.records?(@current_team)} class="measure">
      These people can log in to SAR Duty for {@current_team.name}. They are the members with
      Owner or Editor access in {@service}. Members who are retired or have left cannot log in.
      To add or remove someone, change their access in {@service}. SAR Duty follows within 10 minutes.
    </p>
    <p :if={D4H.records?(@current_team)} class="measure">
      These people can log in to SAR Duty for {@current_team.name}. They are the members who
      are team admins. Members who are retired or have left cannot log in. To add or remove
      someone, change Team admin on their Change member page.
    </p>
    <.team_managers
      id="team-managers"
      managers={@managers}
      grants={@grants}
      login_emails={@login_emails}
    />

    <section :if={@organization} id="organization-admins" class="mt-8 measure">
      <h2 class="heading">{@organization.short_name}'s organization admins</h2>
      <p>
        They keep {@organization.name}'s settings and hours tags, and can turn your ID cards on or
        off. They see your team's totals, never its members.
      </p>
      <p :if={@organization_admins == []} class="hint">None yet.</p>
      <ul :if={@organization_admins != []} id="organization-admin-emails">
        <li :for={{email, i} <- Enum.with_index(@organization_admins)}>
          <.email id={"organization-admin-#{i}-email"} email={email} />
        </li>
      </ul>
    </section>

    <section id="team-contacts" class="mt-8 measure">
      <h2 class="heading">Team contacts</h2>
      <p>
        One or two people members can ask for help. Get help lists them with their email and phone,
        and messages to the team go to them. They do not need to be team admins.
      </p>
      <.form
        for={@contacts_form}
        id="team-contacts-form"
        phx-change="validate_contacts"
        phx-submit="save_contacts"
      >
        <.input
          :for={
            {field, label} <- [
              first_contact_id: "First contact",
              second_contact_id: "Second contact"
            ]
          }
          field={@contacts_form[field]}
          type="combobox"
          label={label}
          options={Enum.map(@contact_choices, &{&1.name, &1.id})}
          prompt="None"
          clearable
        />
        <.form_actions>
          <.button
            id="team-contacts-save"
            variant={:success}
            disabled={@viewing_as != nil}
            phx-disable-with="Saving…"
          >
            Save contacts
          </.button>
        </.form_actions>
      </.form>
    </section>

    <section id="sar-duty-admins" class="mt-8 measure">
      <h2 class="heading">SAR Duty site admins</h2>
      <p>
        They run SAR Duty and can open every team. Reach them at <.a href="mailto:support@sarduty.com">support@sarduty.com</.a>.
      </p>
      <ul id="sar-duty-admin-emails">
        <li :for={{email, i} <- Enum.with_index(@sar_duty_admins)}>
          <.email id={"sar-duty-admin-#{i}-email"} email={email} />
        </li>
      </ul>
    </section>
    """
  end

  def handle_event("validate_contacts", %{"contacts" => params}, socket) do
    changeset =
      socket.assigns.current_team
      |> Team.build_contacts_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_contacts_form(socket, changeset)}
  end

  def handle_event("save_contacts", %{"contacts" => params}, socket) do
    case SaveTeamContacts.call(socket.assigns.current_team, params) do
      {:ok, team} ->
        socket
        |> assign(current_team: team)
        |> assign_saved_contacts(team, DateTime.utc_now())
        |> put_flash(:info, "Saved team contacts.")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign_contacts_form(socket, changeset)}
    end
  end

  defp organization_admins(nil), do: []

  defp organization_admins(organization),
    do: organization |> OrganizationAdmin.get_for_organization() |> Enum.map(& &1.email)
end
