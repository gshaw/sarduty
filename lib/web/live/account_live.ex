defmodule Web.AccountLive do
  @moduledoc """
  Account settings, at /account: who you're logged in as, the maps app place links open
  (#301), and invitation reminders (#444) for each team the user logs in to as a member.
  Team settings live under each team, so the URL names the team they change (#153); the
  account menu reaches them (#312).

  Invitation reminders are the member's setting, so each switch changes the member row
  the user logs in as (`Member.get_logins/2`), looked up again on every tap. A team admin
  viewing a team as a member (#425) sees their own switches, turned off.
  """

  use Web, :live_view_app_layout

  alias App.Model.Member
  alias App.Operation.SetInvitationReminders
  alias App.Operation.SetMapsApp
  alias Web.Components.OpenInMaps
  alias Web.UserAuth

  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Account settings",
       viewing_as?: UserAuth.viewing_as?(session)
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">Account settings</h1>
      <p id="account-email">
        Logged in as {@current_user.email}. Your email and your teams come from D4H.
      </p>
      <form id="maps-app-form" class="mt-8" phx-change="set-maps-app" phx-submit="set-maps-app">
        <fieldset>
          <legend class="subheading">Maps app</legend>
          <p class="hint">Places in SAR Duty open in this app.</p>
          <label
            :for={{app, name} <- [{"google", "Google Maps"}, {"apple", "Apple Maps"}]}
            class="choice"
          >
            <input
              type="radio"
              id={"maps-app-#{app}"}
              name="maps_app"
              value={app}
              checked={@current_user.maps_app == app}
            />
            {name}
          </label>
        </fieldset>
      </form>
      <section :if={@member_logins != []} id="emails" class="mt-8">
        <h2 class="subheading">Emails</h2>
        <p :if={@viewing_as?} id="emails-view-as" class="hint">
          You're viewing a team as a member, so nothing is saved. Stop viewing to change these.
        </p>
        <.switch
          :for={member <- @member_logins}
          id={"invitation-reminders-#{member.team.subdomain}"}
          label={reminders_label(@member_logins, member)}
          checked={member.invitation_reminders}
          disabled={@viewing_as?}
          phx-click="reminders"
          phx-value-id={member.id}
        >
          Team admins at {member.team.name} can email you when you have not replied to an activity.
        </.switch>
      </section>
    </div>
    """
  end

  defp reminders_label([_one], _member), do: "Invitation reminders"
  defp reminders_label(_logins, member), do: "Invitation reminders from #{member.team.name}"

  def handle_event("set-maps-app", %{"maps_app" => app}, socket) do
    case SetMapsApp.call(socket.assigns.current_user, app) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> put_flash(:info, "Places now open in #{OpenInMaps.app_name(user.maps_app)}.")}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("reminders", _params, %{assigns: %{viewing_as?: true}} = socket),
    do: {:noreply, put_flash(socket, :error, "You're viewing as a member, so nothing is saved.")}

  # The member comes from the user's own logins, never from the id alone.
  def handle_event("reminders", %{"id" => id}, socket) do
    %{current_user: user} = socket.assigns
    now = DateTime.utc_now()

    with {id, ""} <- Integer.parse(id),
         %Member{} = member <- Member.get_login(user.email, id, now) do
      SetInvitationReminders.call(member, not member.invitation_reminders)
    end

    {:noreply, assign(socket, :member_logins, Member.get_logins(user.email, now))}
  end
end
