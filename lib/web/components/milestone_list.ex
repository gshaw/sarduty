defmodule Web.Components.MilestoneList do
  @moduledoc """
  A member's milestones (#389), from `App.ViewData.Milestones.build/4`: what they
  reached and the day, with the activity that reached it. A plain list, no badges. See
  /styles/milestone-list.
  """

  use Web, :function_component

  alias Service.Format

  attr :id, :string, required: true
  attr :milestones, :list, required: true

  def milestone_list(assigns) do
    ~H"""
    <ul id={@id} class="divide-y divide-border-subtle">
      <li
        :for={milestone <- @milestones}
        id={"#{@id}-#{milestone.kind}-#{milestone.count}"}
        class="py-2"
      >
        <span class="block font-semibold">{title(milestone)}</span>
        <span class="hint block">{detail(milestone)}</span>
      </li>
    </ul>
    """
  end

  defp title(%{kind: :hours, count: n}), do: "#{Format.number(n)} hours"

  defp title(%{kind: :years, count: n}),
    do: Format.count(n, one: "1 year on the team", many: "%d years on the team")

  defp title(%{kind: :incidents, count: 1}), do: "First incident"
  defp title(%{kind: :incidents, count: n}), do: "#{Format.number(n)} incidents"

  defp detail(%{on: on, activity: nil}), do: Format.date_long(on)
  defp detail(%{on: on, activity: activity}), do: "#{Format.date_long(on)} · #{activity.title}"
end
