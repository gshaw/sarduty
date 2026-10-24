defmodule Web.TakeAttendanceLive do
  use Web, {:live_view_narrow_layout, size: :tool, access: :team}

  alias App.Model.Activity
  alias Service.Format

  # The team's Take attendance page (#475), for an iPad at the hall: the activities
  # taking attendance now as big buttons. With one, it opens that activity's scanner. Its
  # address doesn't change, so a team prints a QR code of it; logged out, it goes to the
  # login page, and logging in comes back here.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()

    case Activity.taking_attendance_now(team, now) do
      [activity] ->
        # Replace, so Back from the scanner doesn't land here and bounce again.
        {:ok, push_navigate(socket, to: scanner_path(team, activity), replace: true)}

      activities ->
        {:ok,
         assign(socket,
           page_title: "Take attendance",
           now: now,
           activities: activities,
           next: if(activities == [], do: Activity.next_after(team, now))
         )}
    end
  end

  @doc """
  Whether a page logging in returns to is a Take attendance page, the team's or an
  activity's, so the login pages say what logging in is for.
  """
  def path?(path) when is_binary(path),
    do: String.match?(path, ~r{^/teams/[^/]+/(activities/[^/]+/)?take-attendance$})

  def path?(_path), do: false

  defp scanner_path(team, activity),
    do: ~p"/teams/#{team}/activities/#{activity.id}/take-attendance"

  def render(assigns) do
    ~H"""
    <h1 class="title">Take attendance</h1>

    <ul :if={@activities != []} id="activities" class="row-links">
      <li :for={activity <- @activities}>
        <.row_link id={"activity-#{activity.id}"} navigate={scanner_path(@current_team, activity)}>
          <strong class="text-link text-lg">{activity.title}</strong>
          <span class="hint block">
            <.activity_kind_mark activity={activity} />
            · {when_text(activity, @current_team, @now)}<span :if={activity.address}> · {activity.address}</span>
          </span>
        </.row_link>
      </li>
    </ul>

    <div :if={@activities == []} id="no-activity">
      <p class="lead">No activity now.</p>
      <p :if={@next} id="next-activity">
        Next is <.a navigate={~p"/teams/#{@current_team}/activities/#{@next.id}"}>{@next.title}</.a>, {when_text(
          @next,
          @current_team,
          @now
        )}. Taking attendance opens at {opens_text(@next, @current_team, @now)}.
      </p>
      <p :if={!@next} id="nothing-coming">Nothing coming up.</p>
    </div>

    <section id="page-address" class="mt-12">
      <h2 class="heading">This page's address</h2>
      <div class="flex flex-wrap gap-2 items-center">
        <.a
          id="page-url"
          href={url(~p"/teams/#{@current_team}/take-attendance")}
          class="font-mono break-all"
        >{url(~p"/teams/#{@current_team}/take-attendance")}</.a>
        <.button
          id="copy-page-url"
          type="button"
          phx-click={JS.dispatch("sarduty:copy", to: "#page-url", detail: %{status: "#copy-status"})}
        >
          Copy link
        </.button>
        <span
          id="copy-status"
          role="status"
          phx-update="ignore"
          class="text-success-text font-semibold"
        ></span>
      </div>
      <p class="hint">
        Add this page to the iPad's Home Screen, or print a QR code of this address for the hall.
        It opens after logging in.
      </p>
    </section>
    """
  end

  defp when_text(activity, team, now) do
    "#{Format.day_coming_up(activity.started_at, now, team.timezone)} " <>
      "#{Format.time_short(activity.started_at, team.timezone)}–" <>
      Format.time_short(activity.finished_at, team.timezone)
  end

  # The time alone when it's the same day as the start, and with its day otherwise.
  defp opens_text(activity, team, now) do
    {opens_at, _closes_at} = Activity.attendance_window(activity)

    if Format.day_coming_up(opens_at, now, team.timezone) ==
         Format.day_coming_up(activity.started_at, now, team.timezone),
       do: Format.time_short(opens_at, team.timezone),
       else: Format.month_day_time(opens_at, team.timezone)
  end
end
