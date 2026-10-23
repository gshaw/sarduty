defmodule Web.Components.ActivityPanel do
  @moduledoc """
  An activity at a glance (#444): its day and time in large type, the counts, the
  member's reply, and Take attendance for team admins. It heads an activity's page, and
  it is the Dashboard's Next up (#205), which adds the title and place and keeps its
  count in that line. See /styles/activity-panel.
  """
  use Web, :function_component

  alias Service.Format
  alias Web.Components.Reply

  attr :id, :string, required: true
  attr :activity, :map, required: true
  attr :team, :map, required: true, doc: "for the time zone, and Take attendance's link"
  attr :now, :any, required: true
  attr :label, :string, default: nil, doc: ~s(a word over the day, such as "Next up")
  attr :counts, :map, default: nil, doc: "`Attendance.reply_counts/2`'s, for the counts line"
  attr :team_admin?, :boolean, default: false, doc: "adds Take attendance"
  slot :inner_block, doc: "what else matters, above the counts, such as the title"
  slot :reply, doc: "the member's reply control, while they can reply"

  def activity_panel(assigns) do
    ~H"""
    <section id={@id} class="card activity-panel">
      <div class="activity-panel-when">
        <span :if={@label} class="hint activity-panel-label">{@label}</span>
        <span class="activity-panel-day">
          {Format.day_coming_up(@activity.started_at, @now, @team.timezone)}
        </span>
        <span class="activity-panel-time">
          {Format.time_short(@activity.started_at, @team.timezone)}
        </span>
      </div>
      <div class="min-w-0">
        {render_slot(@inner_block)}
        <p :if={@counts} id={"#{@id}-counts"} class="activity-panel-counts">
          {Reply.counts_text(@counts, started?(@activity, @now))}
        </p>
        <div :if={@reply != []} class="activity-panel-reply">{render_slot(@reply)}</div>
      </div>
      <.button
        :if={@team_admin? and !@activity.deleted_at}
        id={"#{@id}-take-attendance"}
        variant={:primary}
        navigate={~p"/teams/#{@team}/activities/#{@activity.id}/take-attendance"}
      >
        Take attendance
      </.button>
    </section>
    """
  end

  @doc "Whether the activity has started by `now`: the counts switch to D4H's words."
  def started?(activity, now), do: not DateTime.after?(activity.started_at, now)
end
