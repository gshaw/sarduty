defmodule Web.AttendanceLive do
  use Web, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Sync Attendance")}
  end

  def render(assigns) do
    ~H"""
    <div>
      <hgroup>
        <h1 class="title">Sync Attendance</h1>
        <p class="lead">
          Synchronize activity attendance to D4H from SAR Assist.
        </p>
      </hgroup>
      <section>
        <p>
          0. User can save encrypted D4H Access Token in their profile (v1: Enter token manually).
        </p>
        <p>1. Select D4H event via auto complete and datalist (v1: Enter D4H Event ID manually).</p>
        <p>2. Text area to paste an attendance record copied from Excel.</p>
        <p>
          3 Button to process pasted data in textarea. This calls D4H API to sync members and attendance.
        </p>
        <p>4. Table showing parsed attendance data with status of attendance from D4H.</p>
        <p>5. Button to update D4H attendance to the event.</p>
        <p>
          6. If D4H activity has coordinate show Button to calculate mileage from D4H member address.
        </p>
      </section>
    </div>
    """
  end
end
