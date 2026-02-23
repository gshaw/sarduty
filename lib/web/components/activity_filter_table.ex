defmodule Web.Components.ActivityFilterTable do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H
  import Web.Components.Pagination
  import Web.Components.Table

  alias App.ViewModel.ActivityFilterViewModel

  attr :form, :map, required: true
  attr :paginated, :map, required: true
  attr :sort, :map, required: true
  attr :path_fn, :map, required: true
  attr :team, :map, required: true

  def activity_filter_table(assigns) do
    ~H"""
    <.form for={@form} phx-change="change" class="filter-form">
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
    </.form>

    <div class="table-summary">
      <span class="table-summary-links">
        <.a navigate={@path_fn.(:all)}>All</.a>
        ·
        <.a navigate={@path_fn.(:future)}>Future</.a>
        ·
        <.a navigate={@path_fn.(:past)}>Past</.a>
      </span>
      <span class="table-summary-count">
        {Service.Format.count(@paginated.total_entries, one: "%d activity", many: "%d activities")}
      </span>
    </div>

    <.table
      id="activity_collection"
      rows={@paginated.entries}
      class="w-full table-striped"
      sort={@sort}
      path_fn={@path_fn}
    >
      <:col :let={record} label="Activity" sorts={[{"↓", "id-"}, {"↑", "id"}]}>
        <.a navigate={~p"/#{@team.subdomain}/activities/#{record.id}"}>
          <.activity_title activity={record} />
        </.a>
        <div class="hint">
          {activity_summary(record)}
        </div>
        <.activity_tags activity={record} />
      </:col>
      <:col :let={record} label="Kind" class="w-1/12">
        <.activity_badges activity={record} />
      </:col>
      <:col
        :let={record}
        label="Date"
        align="right"
        class="w-1/12 whitespace-nowrap tabular-nums"
        sorts={[{"↓", "date-"}, {"↑", "date"}]}
      >
        {Service.Format.datetime_short(record.started_at, @team.timezone)}
      </:col>
      <:col
        :let={record}
        label="Duration"
        class="w-1/12 whitespace-nowrap tabular-nums"
        align="right"
        sorts={[{"↓", "hours-"}, {"↑", "hours"}]}
      >
        {Service.Format.duration_as_hours_minutes_short(
          Service.Convert.duration_to_minutes(record.started_at, record.finished_at)
        )}
      </:col>
    </.table>

    <.pagination class="my-p" paginated={@paginated} path_fn={@path_fn} />
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
