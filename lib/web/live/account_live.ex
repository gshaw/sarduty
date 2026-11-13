defmodule Web.AccountLive do
  @moduledoc """
  Account settings, at /account: who you're logged in as, the maps app place links open
  (#301), and invitation reminders (#444) for each team the user logs in to as a member.
  Team settings live under each team, so the URL names the team they change (#153); the
  account menu reaches them (#312).

  Invitation reminders are the member's setting, so each switch changes the member row
  the user logs in as (`Member.get_logins/2`), looked up again on every tap. A team admin
  viewing a team as a member (#425) sees their own switches, turned off.

  Passkeys (#129) are the user's own, so viewing as a member doesn't touch them. The
  PasskeyAdd hook asks for a challenge as the section mounts, runs the browser's prompt,
  and sends back what it made; App.Operation.AddPasskey checks and saves it.
  """

  use Web, :live_view_app_layout

  import Web.Components.Columns, only: [date_cell: 1]

  alias App.Accounts.UserPasskey
  alias App.Accounts.WebAuthn
  alias App.Model.Member
  alias App.Operation.AddPasskey
  alias App.Operation.RemovePasskey
  alias App.Operation.SetInvitationReminders
  alias App.Operation.SetMapsApp
  alias Web.Components.OpenInMaps
  alias Web.SecurityEvent
  alias Web.UserAuth

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Account settings",
       viewing_as?: UserAuth.viewing_as?(session),
       passkey_challenge: nil,
       client_ip: session["client_ip"],
       user_agent: get_connect_info(socket, :user_agent),
       timezone: timezone(socket.assigns),
       now: DateTime.utc_now()
     )
     |> assign_passkeys()}
  end

  defp assign_passkeys(socket),
    do: assign(socket, :passkeys, UserPasskey.list_for(socket.assigns.current_user))

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">Account settings</h1>
      <p id="account-email">
        Logged in as {@current_user.email}. Your email and your teams come from each team's records.
      </p>
      <section id="passkeys" class="mt-8">
        <h2 class="subheading">Passkeys</h2>
        <p class="hint">
          Log in with Face ID, Touch ID, or your phone instead of a code. Codes still work.
        </p>
        <.table
          :if={@passkeys != []}
          id="passkey-list"
          rows={@passkeys}
          row_id={&"passkey-#{&1.id}"}
          class="table-striped"
        >
          <:col :let={passkey} label="Passkey">
            {passkey.name}
            <.hint :if={passkey.added_with}>Added on {passkey.added_with}</.hint>
          </:col>
          <:col :let={passkey} label="Added" class="w-px whitespace-nowrap">
            <.date_cell value={passkey.inserted_at} timezone={@timezone} />
          </:col>
          <:col :let={passkey} label="Last used" class="whitespace-nowrap">
            {Service.Format.days_ago(passkey.last_used_at, @now, @timezone) || "Never"}
          </:col>
          <:col :let={passkey} label="" align="right">
            <.button
              id={"passkey-remove-#{passkey.id}"}
              type="button"
              size={:sm}
              phx-click="remove-passkey"
              phx-disable-with="Removing…"
              phx-value-id={passkey.id}
              data-confirm={"Remove #{passkey.name}? It can no longer log you in."}
              data-confirm-button="Remove passkey"
            >
              Remove
            </.button>
          </:col>
        </.table>
        <p :if={@passkeys == []} id="passkeys-empty">
          No passkeys yet. Add one on your own phone or computer, never a shared one.
        </p>
        <div class="mt-4">
          <.button type="button" id="passkey-add" phx-hook="PasskeyAdd">Add a passkey</.button>
        </div>
      </section>
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

  # Dates in the zone of the team the account menu opens, since a user has no zone.
  defp timezone(%{current_team: %{timezone: timezone}}), do: timezone
  defp timezone(_assigns), do: "Etc/UTC"

  defp reminders_label([_one], _member), do: "Invitation reminders"
  defp reminders_label(_logins, member), do: "Invitation reminders from #{member.team.name}"

  # The browser's options for a new passkey. The challenge stays here for passkey-created.
  def handle_event("passkey-options", _params, socket) do
    %{current_user: user, passkeys: passkeys} = socket.assigns
    challenge = WebAuthn.registration_challenge()
    options = WebAuthn.creation_options(challenge, user, passkeys)
    {:reply, options, assign(socket, :passkey_challenge, challenge)}
  end

  def handle_event(
        "passkey-created",
        params,
        %{assigns: %{passkey_challenge: challenge}} = socket
      )
      when challenge != nil do
    %{current_user: user, user_agent: user_agent} = socket.assigns
    socket = assign(socket, :passkey_challenge, nil)

    case AddPasskey.call(user, challenge, params, user_agent) do
      {:ok, passkey} ->
        record(socket, :passkey_added, passkey)
        {:reply, %{}, socket |> assign_passkeys() |> put_flash(:info, "Passkey added.")}

      {:error, :taken} ->
        {:reply, %{}, put_flash(socket, :error, "This passkey is already on an account.")}

      {:error, _reason} ->
        {:reply, %{},
         put_flash(socket, :error, "SAR Duty could not add that passkey. Try again.")}
    end
  end

  def handle_event("passkey-created", _params, socket), do: {:reply, %{}, socket}

  # The browser refused for a reason other than the person closing its prompt.
  def handle_event("passkey-failed", %{"name" => "InvalidStateError"}, socket),
    do:
      {:noreply, put_flash(socket, :error, "This device already has a passkey for your account.")}

  def handle_event("passkey-failed", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Your browser could not make a passkey. Try again.")}

  def handle_event("remove-passkey", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id),
         {:ok, passkey} <- RemovePasskey.call(socket.assigns.current_user, id) do
      record(socket, :passkey_removed, passkey)
      {:noreply, socket |> assign_passkeys() |> put_flash(:info, "Passkey removed.")}
    else
      _ -> {:noreply, assign_passkeys(socket)}
    end
  end

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

  defp record(socket, kind, passkey) do
    user = socket.assigns.current_user

    SecurityEvent.record(socket.assigns, kind,
      user_id: user.id,
      email_or_phone: user.email,
      data: %{passkey: passkey.name}
    )
  end
end
