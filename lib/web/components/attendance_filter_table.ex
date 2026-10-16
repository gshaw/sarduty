defmodule Web.Components.AttendanceFilterTable do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H
  import Web.Components.FilterBar
  import Web.Components.Pagination
  import Web.Components.Table

  alias App.ViewModel.AttendanceFilterViewModel

  attr :form, :map, required: true
  attr :paginated, :map, required: true
  attr :total_minutes, :integer, required: true
  attr :sort, :string, required: true
  attr :path_fn, :any, required: true
  attr :member, :map, required: true

  def attendance_filter_table(assigns) do
    assigns =
      Phoenix.Component.assign(assigns,
        total_formatted: Service.Format.duration(assigns.total_minutes)
      )

    ~H"""
    <.filter_bar
      for={@form}
      id="attendance_filter_form"
      count={
        Service.Format.count(@paginated.total_entries, one: "%d activity", many: "%d activities")
      }
      total={"#{@total_formatted} total"}
      clear={@path_fn.(:reset)}
      path_fn={@path_fn}
      page={@paginated}
      hidden={[@form[:sort]]}
    >
      <:search field={@form[:q]} />
      <:filter
        field={@form[:when]}
        label="Year"
        options={AttendanceFilterViewModel.when_kinds(@member)}
        default={AttendanceFilterViewModel.current_year()}
      />
      <:filter
        field={@form[:tag]}
        label="Hours tag"
        options={AttendanceFilterViewModel.tag_kinds()}
        default="all"
      />
    </.filter_bar>

    <.table
      :if={Enum.any?(@paginated.entries)}
      id="attendance_collection"
      rows={@paginated.entries}
      class="table-striped"
      sort={@sort}
      path_fn={@path_fn}
    >
      <:col :let={record} label="Activity" sorts={[{"↓", "id-"}, {"↑", "id"}]}>
        <.a navigate={~p"/teams/#{@member.team}/activities/#{record.activity.id}"}>
          <.activity_title activity={record.activity} />
        </.a>
      </:col>
      <:col
        :let={record}
        label="Start"
        align="right"
        class="w-1/12 whitespace-nowrap"
        sorts={[{"↓", "date-"}, {"↑", "date"}]}
      >
        {Service.Format.datetime_short(
          record.started_at,
          @member.team.timezone
        )}
      </:col>
      <:col :let={record} label="Finish" align="right" class="w-1/12 whitespace-nowrap">
        {Service.Format.time_short(
          record.finished_at,
          @member.team.timezone
        )}
      </:col>
      <:col
        :let={record}
        label="Duration"
        align="right"
        class="w-1/12 whitespace-nowrap"
        sorts={[{"↓", "hours-"}, {"↑", "hours"}]}
      >
        {Service.Format.duration(record.duration_in_minutes)}
      </:col>
    </.table>

    <.empty_state
      :if={@paginated.entries == []}
      id="no-attendance"
      title="No activities match"
    >
      Change the search, the year, or the hours tag.
    </.empty_state>

    <.pagination class="my-4" paginated={@paginated} path_fn={@path_fn} />
    """
  end
end
