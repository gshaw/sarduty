defmodule Web.MeActivitiesLive do
  use Web, :live_view_app_layout

  import Web.Components.ActivityList
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
        <.activity_list
          id="signed-up"
          rows={@signed_up}
          timezone={@member.team.timezone}
          href={activity_href(@member.team)}
          external={true}
        />
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
    <section
      :for={{month, rows} <- MemberRecords.by_month(@attendances, @member.team.timezone)}
      id={"month-#{Date.to_iso8601(month)}"}
      class="mb-6"
    >
      <h3 class="subheading">{Service.Format.month(month)}</h3>
      <.activity_list
        id={"attendance-#{Date.to_iso8601(month)}"}
        row_id="attendance"
        rows={rows}
        timezone={@member.team.timezone}
        href={activity_href(@member.team)}
        external={true}
      >
        <:detail :let={attendance}>
          {Service.Format.duration(MemberRecords.minutes(attendance))}
        </:detail>
      </.activity_list>
    </section>
    """
  end

  # A team on SAR Duty Records has no activity page a member can open (docs/records.md).
  defp activity_href(team) do
    if !D4H.records?(team), do: &D4H.activity_url(team, &1)
  end
end
