defmodule Web.Components.ActivityFilterTable do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.Columns
  import Web.Components.D4H
  import Web.Components.FilterBar
  import Web.Components.Pagination
  import Web.Components.StatSwitch
  import Web.Components.Table

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Team
  alias App.ViewModel.ActivityFilterViewModel

  attr :form, :map, required: true
  attr :paginated, :map, required: true
  attr :sort, :map, required: true
  attr :path_fn, :map, required: true
  attr :team, :map, required: true
  attr :kind_counts, :map, required: true, doc: "activities of each kind, from `kind_counts/3`"
  attr :counts, :map, default: %{}, doc: "`Attendance.reply_counts/2` for the page's activities"

  def activity_filter_table(assigns) do
    ~H"""
    <.stat_switch id="activity-switch" label="Kind">
      <:view
        :for={{label, kind} <- kinds(@team, @kind_counts)}
        id={"activity-view-#{kind}"}
        patch={@path_fn.(activity: kind, page: nil)}
        current={@form[:activity].value == kind}
        count={Map.get(@kind_counts, kind, 0)}
        marker={kind != "all" && kind}
      >
        {label}
      </:view>
    </.stat_switch>

    <.filter_bar
      for={@form}
      id="activity_filter_form"
      count={
        Service.Format.count(@paginated.total_entries, one: "%d activity", many: "%d activities")
      }
      repeats={@paginated.total_entries == Map.get(@kind_counts, @form[:activity].value, 0)}
      clear={@path_fn.(:all)}
      path_fn={@path_fn}
      page={@paginated}
      hidden={[@form[:sort], @form[:activity]]}
    >
      <:search field={@form[:q]} />
      <:filter
        field={@form[:when]}
        label="When"
        options={ActivityFilterViewModel.when_kinds(@team)}
        default="all"
      />
      <:filter
        field={@form[:status]}
        label="Status"
        options={ActivityFilterViewModel.status_kinds()}
        default="all"
      />
      <:filter
        field={@form[:hours]}
        label="Hours tag"
        options={ActivityFilterViewModel.hours_kinds()}
        default="all"
      />
      <:filter
        :if={!D4H.records?(@team)}
        field={@form[:fields]}
        label="Required fields"
        options={ActivityFilterViewModel.fields_kinds()}
        default="all"
      />
    </.filter_bar>

    <.activity_table
      rows={@paginated.entries}
      sort={@sort}
      path_fn={@path_fn}
      team={@team}
      hours={@form[:hours].value}
      counts={@counts}
    />

    <.pagination class="my-4" paginated={@paginated} path_fn={@path_fn} />
    """
  end

  attr :id, :string, default: "activity_collection"
  attr :rows, :list, required: true
  attr :sort, :string, required: true
  attr :path_fn, :any, required: true
  attr :team, :map, required: true
  attr :hours, :string, default: nil, doc: "the Hours tag filter, set to list ones to fix"

  attr :counts, :map,
    default: %{},
    doc: "`Attendance.reply_counts/2` by activity id, for the badges after the title (#447)"

  # The activity list's table, without its filters. The style guide shows it with made-up rows.
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

  # Chores only on a team that logs them, or once had chore activities in this view.
  defp kinds(team, kind_counts) do
    chores? = Team.chores?(team) or Map.get(kind_counts, "chores", 0) > 0

    Enum.filter(ActivityFilterViewModel.activity_kinds(), fn {_, kind} ->
      kind != "chores" or chores?
    end)
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
