defmodule Web.Components.ActivityFilterTable do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H
  import Web.Components.FilterBar
  import Web.Components.Pagination
  import Web.Components.Table

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.ViewModel.ActivityFilterViewModel

  attr :form, :map, required: true
  attr :paginated, :map, required: true
  attr :sort, :map, required: true
  attr :path_fn, :map, required: true
  attr :team, :map, required: true

  def activity_filter_table(assigns) do
    ~H"""
    <.filter_bar
      for={@form}
      id="activity_filter_form"
      count={
        Service.Format.count(@paginated.total_entries, one: "%d activity", many: "%d activities")
      }
      clear={@path_fn.(:all)}
      path_fn={@path_fn}
      page={@paginated}
      hidden={[@form[:sort]]}
    >
      <:search field={@form[:q]} />
      <:filter
        field={@form[:activity]}
        label="Kind"
        options={ActivityFilterViewModel.activity_kinds()}
        default="all"
      />
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
    </.filter_bar>

    <.activity_table
      rows={@paginated.entries}
      sort={@sort}
      path_fn={@path_fn}
      team={@team}
      untagged?={@form[:hours].value == "untagged"}
    />

    <.pagination class="my-4" paginated={@paginated} path_fn={@path_fn} />
    """
  end

  attr :id, :string, default: "activity_collection"
  attr :rows, :list, required: true
  attr :sort, :string, required: true
  attr :path_fn, :any, required: true
  attr :team, :map, required: true
  attr :untagged?, :boolean, default: false, doc: "listing activities with no hours tag"

  # The activity list's table, without its filters. The style guide shows it with made-up rows.
  def activity_table(assigns) do
    assigns = assign(assigns, :hours_tags, Activity.hours_tags(assigns.team))

    ~H"""
    <.table
      id={@id}
      rows={@rows}
      class="table-striped"
      sort={@sort}
      path_fn={@path_fn}
    >
      <:col :let={record} label="Activity" sorts={[{"↓", "id-"}, {"↑", "id"}]}>
        <.a navigate={~p"/teams/#{@team}/activities/#{record.id}"}>
          <.activity_title activity={record} />
        </.a>
        <div class="hint">
          {activity_summary(record)}
        </div>
        <.activity_tags activity={record} hours_tags={@hours_tags} />
        <%!-- Needs attention links here, and D4H refuses tags on a published activity (#358). --%>
        <div
          :if={@untagged? and D4H.tags_locked?(@team, record)}
          id={"activity-#{record.id}-tags-in-d4h"}
          class="hint"
        >
          Published, so set its hours tag in D4H.
          <.a external={true} href={D4H.activity_url(@team, record)}>Open D4H activity</.a>
        </div>
      </:col>
      <:col :let={record} label="Kind" class="w-1/12">
        <.activity_kind activity={record} />
      </:col>
      <:col
        :let={record}
        label="Date"
        align="right"
        class="w-1/12 whitespace-nowrap"
        sorts={[{"↓", "date-"}, {"↑", "date"}]}
      >
        {Service.Format.datetime_short(record.started_at, @team.timezone)}
      </:col>
      <:col
        :let={record}
        label="Duration"
        class="w-1/12 whitespace-nowrap"
        align="right"
        sorts={[{"↓", "hours-"}, {"↑", "hours"}]}
      >
        <span :if={activity_hours_type(record, @hours_tags)} class="text-text-muted">
          {activity_hours_type(record, @hours_tags)}
        </span>
        {Service.Format.duration(
          Service.Convert.duration_to_minutes(record.started_at, record.finished_at)
        )}
      </:col>
    </.table>
    """
  end

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
