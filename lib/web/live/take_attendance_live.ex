defmodule Web.TakeAttendanceLive do
  use Web, {:live_view_narrow_layout, size: :tool, access: :team}

  alias App.Model.Activity
  alias Service.Format

  # The team's Take attendance page (#475), for an iPad at the hall: the activities
  # taking attendance now as big buttons. With one, it opens that activity's scanner. It
  # looks again each minute, so an iPad left on it opens the scanner when the window
  # does. Its address doesn't change, so a team prints a QR code of it; logged out, it
  # goes to the login page, and logging in comes back here.
  @tick_ms :timer.minutes(1)

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, @tick_ms)
    {:ok, socket |> assign(page_title: "Take attendance") |> load(DateTime.utc_now())}
  end

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, load(socket, DateTime.utc_now())}
  end

  defp load(socket, now) do
    team = socket.assigns.current_team

    case Activity.taking_attendance_now(team, now) do
      # Replace, so Back from the scanner doesn't land here and bounce again.
      [activity] ->
        push_navigate(socket, to: scanner_path(team, activity), replace: true)

      activities ->
        next = if activities == [], do: Activity.next_after(team, now)
        assign(socket, now: now, activities: activities, next: next)
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
      <.activity_row
        :for={activity <- @activities}
        id={"activity-#{activity.id}"}
        activity={activity}
        navigate={scanner_path(@current_team, activity)}
        team={@current_team}
        now={@now}
      />
    </ul>

    <div :if={@activities == []} id="no-activity">
      <p class="lead">No activity now.</p>
      <div :if={@next} id="next-activity">
        <h2 class="heading">Next activity</h2>
        <ul class="row-links">
          <.activity_row
            id={"next-#{@next.id}"}
            activity={@next}
            navigate={~p"/teams/#{@current_team}/activities/#{@next.id}"}
            team={@current_team}
            now={@now}
          />
        </ul>
        <p id="opens-at">{opens_text(@next, @current_team)}</p>
      </div>
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

  attr :id, :string, required: true
  attr :activity, :any, required: true
  attr :navigate, :string, required: true
  attr :team, :any, required: true
  attr :now, :any, required: true

  defp activity_row(assigns) do
    ~H"""
    <li>
      <.row_link id={@id} navigate={@navigate}>
        <strong class="text-link text-lg">{@activity.title}</strong>
        <span class="hint block">
          <.activity_kind_mark activity={@activity} />
          · {when_text(@activity, @team, @now)}<span :if={@activity.address}> · {@activity.address}</span>
        </span>
      </.row_link>
    </li>
    """
  end

  defp when_text(activity, team, now) do
    "#{Format.day_coming_up(activity.started_at, now, team.timezone)} " <>
      "#{Format.time_short(activity.started_at, team.timezone)}–" <>
      Format.time_short(activity.finished_at, team.timezone)
  end

  # The time alone: the row above has the day, and the window is counted from its start.
  defp opens_text(activity, team) do
    {opens_at, _closes_at} = Activity.attendance_window(activity)
    hours = Format.duration(Activity.attendance_window_hours() * 60)

    "Taking attendance opens at #{Format.time_short(opens_at, team.timezone)}, " <>
      "#{hours} before it starts."
  end
end
