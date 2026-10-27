defmodule Web.Settings.MemberLoginsLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Operation.SetTeamMemberLogins

  # The switch for member logins (#156), /teams/:subdomain/settings/member-logins.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    {:ok, socket |> assign(page_title: "Team settings · Member logins") |> assign_form(team)}
  end

  def handle_event("save", %{"team" => params}, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    enabled = params["member_logins"] == "true"

    options = [
      chores: params["chores_enabled"] == "true",
      certificates: params["certificates_enabled"] == "true"
    ]

    {:ok, team} = SetTeamMemberLogins.call(team, enabled, user, options)

    message =
      if enabled,
        do: "Member logins turned on. Members can log in now.",
        else: "Member logins turned off. Members cannot log in."

    socket =
      socket
      |> assign(current_team: team)
      |> assign_form(team)
      |> put_flash(:info, message)

    {:noreply, socket}
  end

  defp assign_form(socket, team),
    do:
      assign(
        socket,
        :form,
        to_form(
          %{
            "member_logins" => team.member_logins,
            "chores_enabled" => team.chores_enabled,
            "certificates_enabled" => team.certificates_enabled
          },
          as: "team"
        )
      )

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:member_logins} />
    <div class="measure">
      <p class="lead">
        Let your members log in to see their year, their ID card, and their tax credit
        letters.
      </p>
      <p>
        Members log in with the email or mobile number your team has in {@service}. They
        see the Dashboard, the members list, and Your membership, and reply to activities.
        Contact details stay with team admins, apart from their own.
      </p>
      <p class="mb-6">Retired members cannot log in.</p>
      <.form for={@form} id="member-logins-form" phx-submit="save">
        <.input field={@form[:member_logins]} type="checkbox" label="Let members log in" />
        <.input field={@form[:chores_enabled]} type="checkbox" label="Let members log chores" />
        <.input
          field={@form[:certificates_enabled]}
          type="checkbox"
          label="Let members send certificates"
        />
        <.form_actions>
          <.button variant={:success}>Save settings</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end
end
