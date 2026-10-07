defmodule Web.Components.NotAPersonSwitch do
  @moduledoc """
  The member sidebar's "Not a person" switch. It's a live component so every member tab
  gets it without its own handle_event. Suggests the switch for a member who looks like
  a bot.
  """
  use Web, :live_component

  alias App.Model.Member
  alias App.Operation.SetMemberNotAPerson

  def update(%{member: member} = assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:attended?, Member.attended?(member))}
  end

  def handle_event("toggle", _params, socket) do
    member = socket.assigns.member
    updated = SetMemberNotAPerson.call(member.team, member.id, not member.not_a_person)
    {:noreply, assign(socket, member: %{member | not_a_person: updated.not_a_person})}
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="mt-p">
      <.switch
        id={"#{@id}-switch"}
        label="Not a person"
        checked={@member.not_a_person}
        phx-click="toggle"
        phx-target={@myself}
      >
        For a bot or a shared D4H account. SAR Duty leaves it out of member counts, dashboard
        checks, team admins, and attendance at the door.
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
