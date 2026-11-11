defmodule Web.Components.YetToArrive do
  @moduledoc """
  The members who signed up for an activity and have not arrived, with a line counting
  arrivals, and the members here now. For team admins, each yet to arrive has their
  mobile number with Call and Text buttons on touch screens; members see names only,
  since they never see contact details (#475). Yet to arrive is on the team admin's
  Attendance page (#245). Take attendance shows Yet to arrive or Here now under its name
  box, each name with a button that records it (#998).
  """
  use Phoenix.Component

  import Web.Components.Core, only: [button: 1, icon: 1]
  import Web.Components.Phone, only: [call_and_text: 1, phone: 1]

  alias App.Model.AttendanceScan

  # A member Take attendance just recorded from a list stays in its place for a moment,
  # saying so, with Undo, so the names under a finger don't move: `%{member_id:, scan_id:,
  # text:, icon:, row:}`, `row` being what the list showed for them before.

  attr :id, :string, default: "yet-to-arrive"
  attr :yet_to_arrive, :map, required: true, doc: "from App.Operation.BuildYetToArrive"
  attr :contacts?, :boolean, default: false, doc: "mobile numbers with Call and Text"
  attr :tapped, :map, default: nil, doc: "a member just recorded from the list"
  attr :class, :any, default: nil
  slot :action, doc: "each member's button, at the row's right; given the member"

  def yet_to_arrive_list(assigns) do
    assigns =
      assign(
        assigns,
        :rows,
        with_tapped(assigns.yet_to_arrive.yet_to_arrive, assigns.tapped, & &1)
      )

    ~H"""
    <div id={@id} class={@class}>
      <p :if={@rows == []} id={"#{@id}-none"}>
        Everyone who signed up has arrived.
      </p>
      <ul :if={@rows != []} id={"#{@id}-members"}>
        <.name_row
          :for={member <- @rows}
          id={"#{@id}-member-#{member.id}"}
          name={member.name}
          tapped={tapped_for(@tapped, member.id)}
        >
          <:detail :if={@contacts?}>
            <.phone id={"#{@id}-#{member.id}"} phone={member.phone} missing="No mobile number" />
          </:detail>
          <:below :if={@contacts?}>
            <.call_and_text id={"#{@id}-#{member.id}"} phone={member.phone} class="mt-1" />
          </:below>
          {render_slot(@action, member)}
        </.name_row>
      </ul>
      <p id={"#{@id}-count"} class="mt-2 hint">{arrived_text(@yet_to_arrive)}</p>
    </div>
    """
  end

  attr :id, :string, default: "here-now"
  attr :here, :list, required: true, doc: "scans, from App.Operation.BuildYetToArrive"
  attr :timezone, :string, required: true
  attr :tapped, :map, default: nil, doc: "a member just recorded from the list"
  attr :class, :any, default: nil
  slot :action, doc: "each member's buttons; given the member"

  def here_list(assigns) do
    assigns = assign(assigns, :rows, with_tapped(assigns.here, assigns.tapped, & &1.member))

    ~H"""
    <div id={@id} class={@class}>
      <p :if={@rows == []} id={"#{@id}-none"}>Nobody is here.</p>
      <ul :if={@rows != []} id={"#{@id}-members"}>
        <.name_row
          :for={scan <- @rows}
          id={"#{@id}-member-#{scan.member.id}"}
          name={scan.member.name}
          tapped={tapped_for(@tapped, scan.member.id)}
        >
          <:detail>
            Arrived {scan |> AttendanceScan.time() |> Service.Format.time_short(@timezone)}
          </:detail>
          {render_slot(@action, scan.member)}
        </.name_row>
      </ul>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :tapped, :map, default: nil, doc: "this member, just recorded"
  slot :detail, doc: "a hint under the name, such as the mobile number"
  slot :below, doc: "more under the hint, such as Call and Text"
  slot :inner_block, doc: "the row's button"

  @doc """
  A name with a hint under it, and the row's button at the right, the same in every row
  at every width, so a column of buttons lines up under a thumb. Just recorded, it says so
  over the same space, with Undo at the far end, where a second tap on the button can't
  reach it.
  """
  def name_row(assigns) do
    ~H"""
    <li
      id={@id}
      class="relative flex items-center gap-3 py-2 border-b border-border-subtle"
    >
      <div class={["flex-1 min-w-0", @tapped && "invisible"]}>
        <div class="font-semibold">{@name}</div>
        <div :if={@detail != []} class="hint">{render_slot(@detail)}</div>
        {render_slot(@below)}
      </div>
      <div :if={@inner_block != []} class={["flex shrink-0 gap-2", @tapped && "invisible"]}>
        {render_slot(@inner_block)}
      </div>
      <div :if={@tapped} id={"#{@id}-tapped"} class="absolute inset-0 flex items-center gap-3">
        <span role="status" class="flex items-center gap-2 min-w-0 font-semibold text-success-text">
          <.icon name={@tapped.icon} />{@tapped.text}
        </span>
        <.button
          id={"#{@id}-undo"}
          type="button"
          class="ml-auto"
          phx-click="undo"
          phx-value-id={@tapped.scan_id}
        >
          Undo
        </.button>
      </div>
    </li>
    """
  end

  # The list with the member just recorded back in its place, for the moment it says so.
  defp with_tapped(rows, nil, _member), do: rows

  defp with_tapped(rows, tapped, member) do
    if Enum.any?(rows, &(member.(&1).id == tapped.member_id)),
      do: rows,
      else: Enum.sort_by([tapped.row | rows], &String.downcase(member.(&1).name))
  end

  defp tapped_for(%{member_id: id} = tapped, id), do: tapped
  defp tapped_for(_tapped, _id), do: nil

  @doc "The yet to arrive count, like 4 of 11 signed up."
  def count_text(%{yet_to_arrive: members, signed_up: signed_up}),
    do: "#{length(members)} of #{signed_up} signed up"

  defp arrived_text(%{arrived: arrived, walk_ins: 0}),
    do: Service.Format.count(arrived, one: "%d member arrived.", many: "%d members arrived.")

  defp arrived_text(%{arrived: arrived, walk_ins: walk_ins}) do
    Service.Format.count(arrived, one: "%d member arrived", many: "%d members arrived") <>
      ", including #{walk_ins} who did not sign up."
  end
end
