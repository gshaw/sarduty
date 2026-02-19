defmodule Web.Components.AttendanceFilterTable do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H
  import Web.Components.Table

  alias App.ViewModel.AttendanceFilterViewModel

  attr :form, :map, required: true
  attr :records, :list, required: true
  attr :member, :map, required: true

  def attendance_filter_table(assigns) do
    total_minutes = AttendanceFilterViewModel.calculate_total_duration(assigns.records)

    assigns =
      Phoenix.Component.assign(assigns,
        total_minutes: total_minutes,
        total_formatted: Service.Format.duration_as_hours_minutes_medium(total_minutes)
      )

    ~H"""
    <.form for={@form} phx-change="change" class="filter-form">
      <.input
        label="Year"
        field={@form[:when]}
        type="select"
        options={AttendanceFilterViewModel.when_kinds(@member)}
      />
      <.input
        label="Tagged"
        field={@form[:tag]}
        type="select"
        options={AttendanceFilterViewModel.tag_kinds()}
      />

      <span class="filter-form-count">
        {length(@records)} activities · {@total_formatted}
      </span>
    </.form>

    <.table
      id="attendance_collection"
      rows={@records}
      class="w-full table-striped"
    >
      <:col :let={record} label="Activity">
        <.a navigate={~p"/#{@member.team.subdomain}/activities/#{record.activity.id}"}>
          <.activity_title activity={record.activity} />
        </.a>
      </:col>
      <:col :let={record} label="Start" class="w-1/12 whitespace-nowrap">
        <span class="label md:hidden">Start</span>
        <span class="whitespace-nowrap">
          {Service.Format.datetime_short(
            record.started_at,
            @member.team.timezone
          )}
        </span>
      </:col>
      <:col :let={record} label="Finish" class="w-1/12 whitespace-nowrap">
        <span class="label md:hidden">Finish</span>
        <span class="whitespace-nowrap">
          {Service.Format.same_day_datetime(
            record.finished_at,
            record.started_at,
            @member.team.timezone
          )}
        </span>
      </:col>
      <:col :let={record} label="Duration" class="w-1/12" align="right">
        <span class="label md:hidden">Duration</span>
        {Service.Format.duration_as_hours_minutes_short(record.duration_in_minutes)}
      </:col>
    </.table>
    """
  end
end
