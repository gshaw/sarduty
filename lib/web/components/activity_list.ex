defmodule Web.Components.ActivityList do
  @moduledoc """
  A member's activities, one row each: the title, then the day, the kind, and any detail
  (#339). The same list on a member's own pages and anywhere else that lists one member's
  attendance. It takes rows and a time zone, not a team. See /styles/activity-list.
  """

  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H, only: [activity_kind_mark: 1]

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "attendances with their activity"
  attr :timezone, :string, required: true
  attr :row_id, :string, default: nil, doc: "each row's id prefix; the list's id by default"

  attr :href, :any,
    default: nil,
    doc: "a function from an activity to its URL, or nil for no links"

  attr :external, :boolean, default: false, doc: "the links leave SAR Duty, such as to D4H"

  slot :detail, doc: "after the kind, such as the time there; takes the attendance with `:let`"

  def activity_list(assigns) do
    ~H"""
    <ul id={@id} class="divide-y divide-border-subtle">
      <li
        :for={attendance <- @rows}
        id={"#{@row_id || @id}-#{attendance.id}"}
        class="py-2"
      >
        <span class="block">
          <.a :if={@href} href={@href.(attendance.activity)} external={@external}>
            {attendance.activity.title}
          </.a>
          <span :if={!@href}>{attendance.activity.title}</span>
        </span>
        <span class="hint block">
          {Service.Format.date_long(attendance.started_at, @timezone)} ·
          <.activity_kind_mark activity={attendance.activity} />
          <span :if={@detail != []}>· {render_slot(@detail, attendance)}</span>
        </span>
      </li>
    </ul>
    """
  end
end
