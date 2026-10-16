defmodule Web.Components.ActivityFilterTable do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H
  import Web.Components.Pagination
  import Web.Components.Table

  alias App.Model.Activity
  alias App.ViewModel.ActivityFilterViewModel

  attr :form, :map, required: true
  attr :paginated, :map, required: true
  attr :sort, :map, required: true
  attr :path_fn, :map, required: true
  attr :team, :map, required: true

  def activity_filter_table(assigns) do
    ~H"""
    <.filter_form for={@form} id="activity_filter_form">
      <.input field={@form[:q]} label="Search" />
      <.input
        label="Kind"
        field={@form[:activity]}
        type="select"
        options={ActivityFilterViewModel.activity_kinds()}
      />
      <.input
        label="When"
        field={@form[:when]}
        type="select"
        options={ActivityFilterViewModel.when_kinds(@team)}
      />
      <.input
        label="Status"
        field={@form[:status]}
        type="select"
        options={ActivityFilterViewModel.status_kinds()}
      />
      <.input
        label="Hours"
        field={@form[:hours]}
        type="select"
        options={ActivityFilterViewModel.hours_kinds()}
      />
      <.input
        label="Sort"
        field={@form[:sort]}
        type="select"
        options={ActivityFilterViewModel.sort_kinds()}
      />
      <.input
        label="Limit"
        field={@form[:limit]}
        type="select"
        options={ActivityFilterViewModel.limits()}
      />
    </.filter_form>

    <div class="table-summary">
      <span class="table-summary-links">
        <.a id="activities_current_link" navigate={@path_fn.(:current)}>Current</.a>
        ·
        <.a navigate={@path_fn.(:future)}>Future</.a>
        ·
        <.a navigate={@path_fn.(:past)}>Past</.a>
        ·
        <.a navigate={@path_fn.(:all)}>All</.a>
      </span>
      <span class="table-summary-count">
        {Service.Format.count(@paginated.total_entries, one: "%d activity", many: "%d activities")}
      </span>
    </div>

    <.activity_table rows={@paginated.entries} sort={@sort} path_fn={@path_fn} team={@team} />

    <.pagination class="my-4" paginated={@paginated} path_fn={@path_fn} />
    """
  end

  attr :id, :string, default: "activity_collection"
  attr :rows, :list, required: true
  attr :sort, :string, required: true
  attr :path_fn, :any, required: true
  attr :team, :map, required: true

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
        <span :if={hours_type = activity_hours_type(record, @hours_tags)} class="text-text-muted">
          {hours_type}
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
