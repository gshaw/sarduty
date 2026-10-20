defmodule Web.MeActivitiesLive do
  use Web, :live_view_app_layout

  import Web.Components.MeYear

  alias App.Adapter.D4H
  alias App.ViewData.MemberRecords

  # The activities a member attended in a year, by month, and what they're signed up for
  # (#339), /teams/:subdomain/me/activities. `member` comes from the login, never the URL.
  def mount(_params, _session, socket) do
    member = socket.assigns.member
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(:page_title, "Activities")
      |> assign(:years, MemberRecords.years(member, now))
      |> assign(:signed_up, MemberRecords.signed_up(member, now))

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    %{member: member, years: years} = socket.assigns
    year = year!(params["year"], years)

    socket =
      socket
      |> assign(:year, year)
      |> assign(:attendances, MemberRecords.attendances(member, year, DateTime.utc_now()))

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">Activities</h1>

      <%= if @signed_up != [] do %>
        <h2 class="heading">Signed up for</h2>
        <.table id="signed-up" rows={@signed_up} row_id={&"signed-up-#{&1.id}"}>
          <:col :let={attendance} label="Date" class="w-px whitespace-nowrap">
            {Service.Format.date_short(attendance.started_at, @member.team.timezone)}
          </:col>
          <:col :let={attendance} label="Activity">
            <.d4h_activity_link team={@member.team} activity={attendance.activity} />
          </:col>
          <:col :let={attendance} label="Kind" class="w-px whitespace-nowrap max-sm:hidden">
            <.activity_kind_mark activity={attendance.activity} />
          </:col>
        </.table>
        <p class="hint">Hours count once the activity starts.</p>
      <% end %>

      <div class={["heading-row", @signed_up != [] && "mt-8"]}>
        <h2 class="heading">Attended in {@year}</h2>
        <.year_switch years={@years} year={@year} path={~p"/teams/#{@member.team}/me/activities"} />
      </div>
      <.attendance_content attendances={@attendances} year={@year} member={@member} />
    </div>
    """
  end

  defp attendance_content(%{attendances: []} = assigns) do
    ~H"""
    <.empty_state id="no-attendance" title={"No activities in #{@year}"}>
      Activities you attended show here after SAR Duty refreshes from {D4H.service_name(@member.team)}.
    </.empty_state>
    """
  end

  defp attendance_content(assigns) do
    ~H"""
    <p>
      {Service.Format.count(length(@attendances), one: "1 activity", many: "%d activities")} attended.
      Missing one? Tell a team admin, who can fix it in {D4H.service_name(@member.team)}.
    </p>
    <.table
      id="attendance"
      groups={month_groups(@attendances, @member.team.timezone)}
      row_id={&"attendance-#{&1.id}"}
    >
      <:col :let={attendance} label="Date" class="w-px whitespace-nowrap">
        {Service.Format.date_short(attendance.started_at, @member.team.timezone)}
      </:col>
      <:col :let={attendance} label="Activity">
        <.d4h_activity_link team={@member.team} activity={attendance.activity} />
      </:col>
      <:col :let={attendance} label="Kind" class="w-px whitespace-nowrap max-sm:hidden">
        <.activity_kind_mark activity={attendance.activity} />
      </:col>
      <:col :let={attendance} label="Time" align="right" class="w-px whitespace-nowrap">
        {Service.Format.duration(MemberRecords.minutes(attendance))}
      </:col>
    </.table>
    """
  end

  # The year's activities by month, newest first, as table groups titled "October".
  defp month_groups(attendances, timezone) do
    for {month, rows} <- MemberRecords.by_month(attendances, timezone),
        do: %{id: Date.to_iso8601(month), title: Service.Format.month(month), rows: rows}
  end
end
