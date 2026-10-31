defmodule Web.Components.ActivityPanel do
  @moduledoc """
  An activity at a glance (#444): its day and time in large type, the counts, the
  member's reply, and Take attendance for whoever may take it now (#475). It heads an activity's page, and
  it is the Dashboard's Next up (#205), which adds the title and place and keeps its
  count in that line. While it is open, a badge follows the counts: "4 more needed" or
  Full (#447). See /styles/activity-panel.
  """
  use Web, :function_component

  alias App.Model.Activity
  alias Service.Format
  alias Web.Components.Reply

  attr :id, :string, required: true
  attr :activity, :map, required: true
  attr :team, :map, required: true, doc: "for the time zone, and Take attendance's link"
  attr :now, :any, required: true
  attr :label, :string, default: nil, doc: ~s(a word over the day, such as "Next up")
  attr :counts, :map, default: nil, doc: "`Attendance.reply_counts/2`'s, for the counts line"

  attr :take_attendance?, :boolean,
    default: false,
    doc: "adds Take attendance: `Activity.take_attendance?/3`"

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
          <span class="with-badge">
            {Reply.counts_text(@counts, Activity.started?(@activity, @now))}
            <.need_badge id={"#{@id}-need"} activity={@activity} counts={@counts} now={@now} />
          </span>
        </p>
        <div :if={@reply != []} class="activity-panel-reply">{render_slot(@reply)}</div>
      </div>
      <.button
        :if={@take_attendance?}
        id={"#{@id}-take-attendance"}
        variant={:primary}
        navigate={~p"/teams/#{@team}/activities/#{@activity.id}/take-attendance"}
      >
        Take attendance
      </.button>
    </section>
    """
  end

  attr :id, :string, default: nil
  attr :activity, :map, required: true, doc: "an Activity, with Enough at and Full at"

  attr :counts, :map,
    required: true,
    doc: "the counts the page shows: `ActivityMembers.counts/1` or `Attendance.reply_counts/2`'s"

  attr :now, :any, required: true

  @doc """
  "4 more needed" in amber while fewer than Enough at have signed up, or Full in grey from
  Full at on (#447). Nothing once the activity starts. Put it in a `.with-badge` after its
  text.
  """
  def need_badge(assigns) do
    assigns =
      assign(assigns,
        more: Activity.more_needed(assigns.activity, assigns.counts, assigns.now),
        full?: Activity.full?(assigns.activity, assigns.counts, assigns.now)
      )

    ~H"""
    <.badge :if={@more} id={@id} kind={:warning}>
      {Format.count(@more, one: "%d more needed", many: "%d more needed")}
    </.badge>
    <.badge :if={@full?} id={@id}>Full</.badge>
    """
  end
end
