defmodule Web.AttendanceLive do
  use Web, :live_view

  alias Service.D4H

  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Attendance",
        d4h_access_token: System.get_env("D4H_ACCESS_TOKEN"),
        d4h_api_host: "api.ca.d4h.org",
        d4h_activity_id: "239224",
        activity: nil,
        selected_attendance_ids: []
      )

    {:ok, socket}
  end

  def render(%{:activity => activity} = assigns) when not is_nil(activity) do
    ~H"""
    <.title_block />
    <.activity_description activity={@activity} />
    <.activity_attendance
      selected_attendance_ids={@selected_attendance_ids}
      attendance_records={@attendance_records}
    />
    """
  end

  def render(assigns) do
    ~H"""
    <.title_block />
    <form phx-submit="search">
      <div class="md:w-1/2">
        <.input
          label="D4H Access Token"
          type="password"
          name="d4h_access_token"
          value={@d4h_access_token}
          autocomplete="off"
        />
        <.input label="D4H API Host" name="d4h_api_host" value={@d4h_api_host} />
        <.input label="D4H Activity ID" name="d4h_activity_id" value={@d4h_activity_id} />
      </div>
      <.button class="btn-success">Look up event</.button>
    </form>
    """
  end

  def activity_description(assigns) do
    ~H"""
    <section class="mb-4">
      <h2 class="heading"><%= @activity.title %></h2>
      <details class="mb-4">
        <summary>Details</summary>
        <pre class="text-sm"><%= inspect(@activity, pretty: true) %></pre>
      </details>
    </section>
    """
  end

  def activity_attendance(assigns) do
    ~H"""
    <section class="mb-4">
      <h2 class="subheading">Attendance</h2>

      <details class="mb-4">
        <summary>Details</summary>
        <pre class="text-sm"><%= inspect(@attendance_records, pretty: true) %></pre>
      </details>

      <div>
        <.table id="attendance_records" rows={@attendance_records}>
          <:col :let={record} label="">
            <.input
              type="checkbox"
              name={record.d4h_attendance_id}
              checked={Enum.member?(@selected_attendance_ids, "#{record.d4h_attendance_id}")}
              phx-click="toggle-attendance"
              phx-value-attendance-id={record.d4h_attendance_id}
            />
          </:col>
          <:col :let={record} label="Name"><%= record.member.name %></:col>
          <:col :let={record} label="Email"><%= record.member.email %></:col>
          <:col :let={record} label="Phone"><%= record.member.phone %></:col>
        </.table>
        <div class="my-4">
          <.button
            disabled={!Enum.any?(@selected_attendance_ids)}
            class="btn-danger"
            phx-click="remove-attendance"
          >
            Remove attendance
          </.button>
        </div>
      </div>
    </section>
    """
  end

  def attendance_details(assigns) do
    ~H"""
    <tr>
      <td><%= @attendance %></td>
    </tr>
    """
  end

  def title_block(assigns) do
    ~H"""
    <hgroup class="mb-8">
      <h1 class="title">Attendance</h1>
      <p class="lead">
        Synchronize activity attendance to D4H from SAR Assist.
      </p>
    </hgroup>
    """
  end

  def handle_event("toggle-attendance", %{"attendance-id" => d4h_attendance_id}, socket) do
    ids = socket.assigns.selected_attendance_ids

    ids =
      if Enum.member?(ids, d4h_attendance_id) do
        IO.inspect("delete: #{d4h_attendance_id}")
        List.delete(ids, d4h_attendance_id)
      else
        IO.inspect("add: #{d4h_attendance_id}")
        [d4h_attendance_id | ids]
      end

    IO.inspect(ids)

    socket = assign(socket, selected_attendance_ids: ids)

    {:noreply, socket}
  end

  def handle_event("attendance-changed", params, socket) do
    socket = assign(socket, selected_attendance_ids: determine_selected_attendance_ids(params))

    {:noreply, socket}
  end

  def handle_event("remove-attendance", params, socket) do
    config = D4H.build_config()

    for attendance_id <- socket.assigns.selected_attendance_ids do
      IO.inspect(attendance_id, label: "remove-attendance")
      D4H.remove_attendance!(config, attendance_id)
    end

    attendance_records = D4H.fetch_attendance!(config, socket.assigns.d4h_activity_id)

    socket =
      assign(
        socket,
        attendance_records: attendance_records,
        selected_attendance_ids: []
      )

    {:noreply, socket}
  end

  def handle_event("search", %{"d4h_activity_id" => d4h_activity_id}, socket) do
    config = D4H.build_config()
    activity = D4H.fetch_activity!(config, d4h_activity_id)
    attendance_records = D4H.fetch_attendance!(config, d4h_activity_id)

    socket =
      assign(
        socket,
        d4h_activity_id: d4h_activity_id,
        activity: activity,
        attendance_records: attendance_records
      )

    {:noreply, socket}
  end

  defp determine_selected_attendance_ids(params) do
    Map.filter(params, fn {_k, v} -> v == "true" end) |> Enum.map(fn {k, _v} -> k end)
  end
end
