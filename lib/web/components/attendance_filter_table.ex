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
    assigns =
      Phoenix.Component.assign(assigns,
        total_hours: AttendanceFilterViewModel.calculate_total_hours(assigns.records)
      )

    ~H"""
    <.form for={@form} phx-change="change" class="filter-form">
      <.input
        label="When"
        field={@form[:when]}
        type="select"
        options={AttendanceFilterViewModel.when_kinds(@member)}
      />
      <.input
        label="Kind"
        field={@form[:tag]}
        type="select"
        options={AttendanceFilterViewModel.tag_kinds()}
      />

      <span class="filter-form-count">
        {length(@records)} activities · {@total_hours} hours
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
      <:col :let={record} label="Started" class="w-1/12 whitespace-nowrap">
        <span class="label md:hidden">Started</span>
        <span class="whitespace-nowrap">
          {Service.Format.short_datetime(
            record.started_at,
            @member.team.timezone
          )}
        </span>
      </:col>
      <:col :let={record} label="Finished" class="w-1/12 whitespace-nowrap">
        <span class="label md:hidden">Finished</span>
        <span class="whitespace-nowrap">
          {Service.Format.attendance_datetime(
            record.finished_at,
            record.started_at,
            @member.team.timezone
          )}
        </span>
      </:col>
      <:col :let={record} label="Hours" class="w-1/12" align="right">
        <span class="label md:hidden">Hours</span>
        {Service.Convert.duration_to_hours(record.started_at, record.finished_at)}
      </:col>
    </.table>
    """
  end
end
