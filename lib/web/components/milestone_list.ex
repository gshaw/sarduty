defmodule Web.Components.MilestoneList do
  @moduledoc """
  A member's milestones (#389), from `App.ViewData.Milestones.build/5`: what they
  reached and the day, with the activity that reached it. Each kind has a grey icon. One
  reached in the last 30 days gets a green New tag: the word says why it stands out, and
  amber already means expiring on the same page (decided 2026-10-23).
  See /styles/milestone-list.
  """

  use Web, :function_component

  alias Service.Format

  attr :id, :string, required: true
  attr :milestones, :list, required: true
  attr :today, Date, default: nil, doc: "in the team's zone; nil marks none as new"

  def milestone_list(assigns) do
    ~H"""
    <ul id={@id} class="milestone-list">
      <li :for={milestone <- @milestones} id={"#{@id}-#{milestone.kind}-#{milestone.count}"}>
        <span class="milestone-icon"><.icon name={icon_name(milestone.kind, :mini)} /></span>
        <span class="min-w-0">
          <span class="block font-semibold">
            {title(milestone)}
            <.badge :if={new?(milestone, @today)} kind={:primary}>New</.badge>
          </span>
          <span class="hint block">{detail(milestone)}</span>
        </span>
      </li>
    </ul>
    """
  end

  @new_days 30

  defp new?(_milestone, nil), do: false
  defp new?(milestone, today), do: Date.diff(today, milestone.on) <= @new_days

  @doc """
  The kind's icon: `:mini` in the list, `:micro` beside a word. Written out in full, as
  Tailwind builds only the icon classes it finds in the source.
  """
  def icon_name(:hours, :mini), do: "hero-clock-mini"
  def icon_name(:years, :mini), do: "hero-cake-mini"
  def icon_name(:incidents, :mini), do: "hero-lifebuoy-mini"
  def icon_name(:hours, :micro), do: "hero-clock-micro"
  def icon_name(:years, :micro), do: "hero-cake-micro"
  def icon_name(:incidents, :micro), do: "hero-lifebuoy-micro"

  @doc ~s(What was reached: "2,000 hours", "10 years on the team", "First incident".)
  def title(%{kind: :hours, count: n}), do: Format.duration(n * 60)

  def title(%{kind: :years, count: n}),
    do: Format.count(n, one: "1 year on the team", many: "%d years on the team")

  def title(%{kind: :incidents, count: 1}), do: "First incident"
  def title(%{kind: :incidents, count: n}), do: "#{Format.number(n)} incidents"

  defp detail(%{on: on, activity: nil}), do: Format.date_long(on)
  defp detail(%{on: on, activity: activity}), do: "#{Format.date_long(on)} · #{activity.title}"
end
