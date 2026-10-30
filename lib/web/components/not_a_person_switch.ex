defmodule Web.Components.NotAPersonSwitch do
  @moduledoc """
  The "Not a person" switch in a member's standing (#366). Suggests the switch for a
  member who looks like a bot. Pass `user`, the team admin who changes it, for the
  member's history.
  """
  use Web, :live_component

  alias App.Model.Member
  alias App.Operation.SetMemberNotAPerson

  def update(%{member: member} = assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:attended?, Member.attended?(member))}
  end

  def handle_event("toggle", _params, socket) do
    %{member: member, user: user} = socket.assigns

    {:ok, updated} =
      SetMemberNotAPerson.call(member.team, member.id, user, not member.not_a_person)

    send(self(), {:not_a_person_changed, updated.not_a_person})
    {:noreply, assign(socket, member: %{member | not_a_person: updated.not_a_person})}
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="mt-4">
      <.switch
        id={"#{@id}-switch"}
        label="Not a person"
        checked={@member.not_a_person}
        phx-click="toggle"
        phx-target={@myself}
      >
        For a bot or a shared account. It logs in and gets email like any member, as a team
        admin if it has that access. SAR Duty never counts it or offers it when you pick
        people.
      </.switch>
      <p
        :if={Member.looks_like_not_a_person?(@member, @attended?)}
        id={"#{@id}-suggestion"}
        class="hint mt-2"
      >
        This looks like a bot: no email, no mobile phone, and no attendance.
      </p>
    </div>
    """
  end
end
