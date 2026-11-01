defmodule Web.Components.ActivityTable do
  @moduledoc """
  The activity list's table (#784). Activities draws its tiles, filters, and pages from
  its report; these are its cells. The header sorts are the report's sorts by name.
  """
  use Web, :function_component

  import Web.Components.A
  import Web.Components.Columns
  import Web.Components.D4H
  import Web.Components.Table

  alias App.Model.Activity

  attr :id, :string, default: "activity_collection"
  attr :rows, :list, required: true
  attr :sort, :string, required: true
  attr :path_fn, :any, required: true
  attr :team, :map, required: true
  attr :hours, :string, default: nil, doc: "the Hours tag filter, set to list ones to fix"

  attr :counts, :map,
    default: %{},
    doc: "`Attendance.reply_counts/2` by activity id, for the badges after the title (#447)"

  # The style guide shows it with made-up rows.
  def activity_table(assigns) do
    assigns = assign(assigns, :hours_tags, Activity.hours_tags(assigns.team))

    ~H"""
    <.table
      id={@id}
      rows={@rows}
      row_id={&"activity-#{&1.id}"}
      class="table-striped"
      sort={@sort}
      path_fn={@path_fn}
    >
      <:col :let={record} label="Activity" sorts={[{"↓", "id-"}, {"↑", "id"}]}>
        <.activity_cell activity={record} team={@team} kind={false} counts={@counts[record.id]} />
        <div class="hint">
          {activity_summary(record)}
        </div>
        <.activity_tags activity={record} hours_tags={@hours_tags} />
        <%!-- Needs attention links here, and a published activity is locked (#358, #585). --%>
        <div
          :if={@hours in ["untagged", "two"] and Activity.locked?(record)}
          id={"activity-#{record.id}-tags-locked"}
          class="hint"
        >
          {if @hours == "two",
            do: "Published, so unpublish it to change its tags.",
            else: "Published, so unpublish it to set its hours tag."}
          <.a navigate={~p"/teams/#{@team}/activities/#{record.id}/edit"}>Change activity</.a>
        </div>
      </:col>
      <:col :let={record} label="Kind" class="w-1/12">
        <.activity_kind activity={record} />
      </:col>
      <:col
        :let={record}
        label="Date"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "date-"}, {"↑", "date"}]}
      >
        <.date_cell activity={record} timezone={@team.timezone} times />
      </:col>
      <:col
        :let={record}
        label="Hours"
        class="w-px whitespace-nowrap"
        align="right"
        sorts={[{"↓", "hours-"}, {"↑", "hours"}]}
      >
        <span :if={activity_hours_type(record, @hours_tags)} class="text-text-muted">
          {activity_hours_type(record, @hours_tags)}
        </span>
        <.hours_cell minutes={duration_minutes(record)} />
      </:col>
    </.table>
    """
  end

  # A chore activity lasts no time: its duration is its members' chores (#575).
  defp duration_minutes(%{chore_minutes: minutes}) when is_integer(minutes), do: minutes

  defp duration_minutes(activity),
    do: Service.Convert.duration_to_minutes(activity.started_at, activity.finished_at)

  def activity_summary(activity) do
    case activity.description do
      nil ->
        ""

      description ->
        description
        |> Service.StringHelpers.strip_html()
        |> Service.StringHelpers.truncate(max_length: 120)
    end
  end
end
