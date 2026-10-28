defmodule Web.TakeAttendanceLive do
  use Web, {:live_view_app_layout, access: :team}

  import Web.Components.CopyButton

  alias App.Model.Activity
  alias Service.Format

  # The team's Take attendance page (#475): the activities taking attendance now, and
  # what's coming up. Every row opens its scanner, which says when a member can start. It
  # never opens a scanner by itself, so the page always says what it is. It looks again
  # each minute, so an activity moves to Now when its window opens. Its address doesn't
  # change, so a team prints a QR code of it; logged out, it goes to the login page, and
  # logging in comes back here. It sits in the app layout, as the side navigation's other
  # pages do; the scanner it opens is the narrow page. Beside the lists, Open on the iPad
  # has the QR code, for a computer only: a touch screen is the device already.
  @tick_ms :timer.minutes(1)

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, @tick_ms)
    url = Web.Endpoint.url() <> ~p"/teams/#{socket.assigns.current_team}/take-attendance"

    {:ok,
     socket
     |> assign(page_title: "Take attendance", url: url, qr_code: qr_code(url))
     |> load(DateTime.utc_now())}
  end

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, load(socket, DateTime.utc_now())}
  end

  defp load(socket, now) do
    team = socket.assigns.current_team

    assign(socket,
      now: now,
      activities: Activity.taking_attendance_now(team, now),
      coming_up: Activity.taking_attendance_later(team, now)
    )
  end

  @doc """
  Whether a page logging in returns to is a Take attendance page, the team's or an
  activity's, so the login pages say what logging in is for.
  """
  def path?(path) when is_binary(path),
    do: String.match?(path, ~r{^/teams/[^/]+/(activities/[^/]+/)?take-attendance$})

  def path?(_path), do: false

  defp qr_code(url), do: url |> EQRCode.encode(:m) |> EQRCode.svg(viewbox: true, color: "#000")

  defp scanner_path(team, activity),
    do: ~p"/teams/#{team}/activities/#{activity.id}/take-attendance"

  def render(assigns) do
    ~H"""
    <h1 class="title">Take attendance</h1>
    <p id="intro" class="lead">
      Scan ID cards as members arrive and leave.
    </p>

    <div class="md:flex md:gap-8">
      <div class="md:w-2/3 min-w-0">
        <.lists activities={@activities} coming_up={@coming_up} team={@current_team} now={@now} />
      </div>
      <aside id="open-on-ipad" class="md:w-1/3 mt-8 pointer-coarse:hidden">
        <h2 class="heading">Open on the iPad</h2>
        <div class="qr-code mb-4" aria-hidden="true">{raw(@qr_code)}</div>
        <p>Scan the code with the iPad's camera, or open this address on it:</p>
        <p class="hint">
          <.copy_button
            id="ipad-address"
            value={@url}
            label="Copy link"
            text={String.replace(@url, ~r{^https?://}, "")}
          />
        </p>
        <p class="hint mb-0">
          Print the code for the hall. It opens this page, and the address never changes.
        </p>
      </aside>
    </div>
    """
  end

  attr :activities, :list, required: true
  attr :coming_up, :list, required: true
  attr :team, :any, required: true
  attr :now, :any, required: true

  defp lists(assigns) do
    ~H"""
    <section id="now" class="mt-8">
      <h2 class="heading">Now</h2>
      <ul :if={@activities != []} id="activities" class="row-links">
        <.activity_row
          :for={activity <- @activities}
          id={"activity-#{activity.id}"}
          activity={activity}
          navigate={scanner_path(@team, activity)}
          team={@team}
          now={@now}
        />
      </ul>
      <p :if={@activities == []} id="no-activity">No activity now.</p>
    </section>

    <section id="coming-up" class="mt-8">
      <h2 class="heading">Coming up</h2>
      <%= if @coming_up != [] do %>
        <p id="opens-at" class="hint">
          Taking attendance opens {Format.duration(Activity.attendance_window_hours() * 60)} before each starts.
        </p>
        <ul class="row-links">
          <.activity_row
            :for={activity <- @coming_up}
            id={"coming-#{activity.id}"}
            activity={activity}
            navigate={scanner_path(@team, activity)}
            team={@team}
            now={@now}
          />
        </ul>
      <% else %>
        <p id="nothing-coming">Nothing coming up.</p>
      <% end %>
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
end
