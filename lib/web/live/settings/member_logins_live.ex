defmodule Web.Settings.MemberLoginsLive do
  use Web, :live_view_narrow_layout

  alias App.Operation.SetTeamMemberLogins

  # The switch for member logins (#156), /teams/:subdomain/settings/member-logins.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    {:ok, socket |> assign(page_title: "Member logins") |> assign_form(team)}
  end

  def handle_event("save", %{"team" => params}, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    enabled = params["member_logins"] == "true"
    {:ok, team} = SetTeamMemberLogins.call(team, enabled, user)

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
    do: assign(socket, :form, to_form(%{"member_logins" => team.member_logins}, as: "team"))

  def render(assigns) do
    ~H"""
    <div>
      <.back_link navigate={~p"/teams/#{@current_team}/settings"}>Team settings</.back_link>
      <h1 class="heading">Member logins</h1>
      <p class="lead">
        Let your members log in to get their own ID card and tax credit letters.
      </p>
      <p>
        Each member sees only their own ID card and letters. They log in with the email or
        mobile number D4H has for them.
      </p>
      <p class="mb-6">Members who have left or retired cannot log in.</p>
      <.form for={@form} id="member-logins-form" phx-submit="save">
        <.input field={@form[:member_logins]} type="checkbox" label="Let members log in" />
        <.form_actions>
          <.button variant={:success}>Save settings</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end
end
