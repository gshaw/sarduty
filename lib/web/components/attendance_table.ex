defmodule Web.Components.AttendanceTable do
  use Web, :function_component

  import Web.Components.Table

  attr :attendance_records, :list, required: true
  attr :status, :string, default: "all"

  def attendance_table(assigns) do
    ~H"""
    <.table
      id="attendance_collection"
      rows={filter_attendance(@attendance_records, @status)}
      class="table-striped"
    >
      <:col :let={record} :if={@status == "all"} label="">
        <span class=""><%= attendance_status_emoji(record.status) %></span>
      </:col>
      <:col :let={record} label="Member">
        <%= record.member.name %>
      </:col>
      <:col :let={record} label="Email">
        <%= record.member.email %>
      </:col>
    </.table>
    <p class="my-1"><%= filter_attendance(@attendance_records, @status) |> Enum.count() %> members</p>
    """
  end

  defp attendance_status_emoji("attending"), do: "✅"
  defp attendance_status_emoji("absent"), do: "❌"
  defp attendance_status_emoji(_status), do: "❔"

  defp filter_attendance(attendance_records, "all"), do: attendance_records

  defp filter_attendance(attendance_records, status),
    do: Enum.filter(attendance_records, &(&1.status == status))
end
