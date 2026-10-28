defmodule Web.InvitationRemindersLive do
  use Web, :live_view_narrow_layout

  alias App.Model.Member
  alias App.Operation.SetInvitationReminders
  alias App.Repo
  alias Web.Navigation
  alias Web.ReplyLinks

  # Where a reminder's "Turn off invitation reminders" goes (#444): no login, only the
  # link's token, for one member. Opening it changes nothing; the button does, and the
  # same page turns them back on. A mail app's own unsubscribe posts to this URL instead
  # (InvitationRemindersController). The setting is the member's, in account settings.
  # Logged in to the link's team, the bar names it.
  def mount(%{"token" => token}, _session, socket) do
    member =
      case ReplyLinks.verify_reminders(token) do
        {:ok, member_id} -> Member |> Repo.get(member_id) |> Repo.preload(:team)
        :error -> nil
      end

    {:ok, socket |> assign(member: member, page_title: title(member)) |> assign_bar_team()}
  end

  defp assign_bar_team(%{assigns: %{member: %Member{team: team}}} = socket) do
    if Navigation.opens_team?(socket.assigns, team),
      do: assign(socket, current_team: team),
      else: socket
  end

  defp assign_bar_team(socket), do: socket

  defp title(nil), do: "This link does not work"
  defp title(%Member{invitation_reminders: true}), do: "Turn off invitation reminders?"
  defp title(%Member{invitation_reminders: false}), do: "Invitation reminders are off"

  def handle_event("set", %{"on" => on}, socket) when on in ["true", "false"] do
    member = SetInvitationReminders.call(socket.assigns.member, on == "true")
    {:noreply, assign(socket, member: member, page_title: title(member))}
  end

  def render(%{member: nil} = assigns) do
    ~H"""
    <h1 class="title">This link does not work</h1>
    <%= if @current_user do %>
      <p>Change your invitation reminders in account settings.</p>
      <p>
        <.a id="reminders-account" href={~p"/account"}>Open account settings</.a>
      </p>
    <% else %>
      <p>Log in to change your invitation reminders.</p>
      <p>
        <.a id="reminders-login" href={~p"/login"}>Log in</.a>
      </p>
    <% end %>
    """
  end

  def render(assigns) do
    ~H"""
    <p class="hint mb-1">{@member.team.name} · {@member.name}</p>
    <h1 class="title mb-2">{@page_title}</h1>
    <div :if={@member.invitation_reminders}>
      <p class="mb-4">
        Team admins at {@member.team.name} can email you when you have not replied to an activity.
      </p>
      <.button
        id="reminders-off"
        variant={:primary}
        phx-click="set"
        phx-value-on="false"
        phx-disable-with="Turning off…"
      >
        Turn off reminders
      </.button>
    </div>
    <div :if={!@member.invitation_reminders}>
      <p class="mb-4">You still see your invitations in SAR Duty.</p>
      <.button id="reminders-on" phx-click="set" phx-value-on="true" phx-disable-with="Turning on…">
        Turn on reminders
      </.button>
      <p class="mt-6 mb-0">
        <.a id="reminders-account" href={~p"/account"}>Open account settings</.a>
        <span :if={!@current_user} class="hint">(log in)</span>
      </p>
    </div>
    """
  end
end
