defmodule Web.ActivityTakeAttendanceLive do
  # Members take attendance too (#475): a scan, a pick, and an undo are theirs. The
  # camera hook in qr_scanner.js sends `scanned` and `scan_failed`.
  use Web,
      {:live_view_narrow_layout,
       size: :tool,
       access: :team,
       view_events: ~w(set_kind change clear_override toggle_yet_to_arrive scan_failed),
       member_events: ~w(scanned pick undo)}

  import Web.Components.Scanner
  import Web.Components.YetToArrive

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.AttendanceScan
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Operation.BuildYetToArrive
  alias App.Operation.RecordAttendanceScan
  alias App.Repo

  # Taking attendance for one activity (#475): team admins at any time, and members from 2
  # hours before it starts until 2 hours after it ends (Activity.take_attendance?/3). It
  # records ID card scans and members picked by name, and lists what it has recorded so a
  # mistake can be undone. Every scan and Undo checks again, and so does a tick each
  # minute, so a page left open opens and stops with the window. Nothing reaches D4H
  # until a team admin sends it from the Attendance page.
  @max_name_matches 8
  @recent_count 30
  # A good scan's confirmation shows this long, then the page is ready for the next.
  @confirm_ms 3000
  @tick_ms :timer.minutes(1)

  def mount(%{"id" => id}, _session, socket) do
    activity = socket.assigns.current_team |> Activity.find!(id) |> Repo.preload(:team)

    if Activity.deleted?(activity),
      do: {:ok, Web.ActivityLive.leave_deleted(socket, activity)},
      else: {:ok, open(socket, activity)}
  end

  defp open(socket, activity) do
    now = DateTime.utc_now()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, AttendanceScan.topic(activity.id))
      Process.send_after(self(), :tick, @tick_ms)
    end

    members =
      activity.team_id
      |> Member.get_all()
      |> Enum.filter(&(Member.current?(&1, now) and not &1.not_a_person))

    socket
    |> assign(
      page_title: "#{activity.title} · Take attendance",
      activity: activity,
      recorder: recorder(socket.assigns, now),
      others_now?: others_now?(activity, now),
      team: activity.team,
      members: members,
      kind: "arrived",
      override: "",
      search: "",
      matches: [],
      message: nil,
      scan_failed: false,
      show_yet_to_arrive: false
    )
    |> assign_closed(now)
    |> load_scans()
  end

  # Why the door can't take attendance now, or nil when it can.
  defp assign_closed(socket, now) do
    case socket |> door() |> RecordAttendanceScan.check_open(now) do
      :ok -> assign(socket, closed: nil)
      {:error, reason} -> assign(socket, closed: reason)
    end
  end

  # The member who takes attendance, so Recorded by names them: the user's member login,
  # or a team admin's member on a team with member logins off, found as replies find them.
  defp recorder(%{current_member: %Member{} = member}, _now), do: member

  defp recorder(%{current_team: team, current_user: user}, now),
    do: Member.find_by_email(team, user.email, now)

  # Who takes attendance, for RecordAttendanceScan.
  defp door(socket) do
    %{
      activity: socket.assigns.activity,
      user: socket.assigns.current_user,
      member: socket.assigns.recorder,
      team_admin?: socket.assigns.team_admin?
    }
  end

  def handle_info(:attendance_scans_changed, socket), do: {:noreply, load_scans(socket)}

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_ms)
    now = DateTime.utc_now()
    socket = reload(socket, now)
    {:noreply, assign(socket, others_now?: others_now?(socket.assigns.activity, now))}
  end

  # Only clears the confirmation it was set for, not a newer one.
  def handle_info({:clear_message, message}, socket) do
    if socket.assigns[:message] == message,
      do: {:noreply, assign(socket, message: nil)},
      else: {:noreply, socket}
  end

  def handle_event("set_kind", %{"kind" => kind}, socket) when kind in ["arrived", "left"],
    do: {:noreply, assign(socket, kind: kind, message: nil)}

  def handle_event("change", params, socket) do
    search = params["search"] || ""

    {:noreply,
     assign(socket,
       override: params["override"] || "",
       search: search,
       matches: if(card_text?(search), do: [], else: matches(socket.assigns.members, search))
     )}
  end

  def handle_event("clear_override", _params, socket),
    do: {:noreply, assign(socket, override: "")}

  # The scanner sends the time box's value with each read, so the scan uses what the
  # box shows even when the phone never sent a change for it.
  def handle_event("scanned", %{"code" => input} = params, socket) do
    kind = socket.assigns.kind
    override = params["override"] || socket.assigns.override
    hosts = Web.VerifyHost.trusted_hosts()

    socket =
      record(socket, fn door, now ->
        RecordAttendanceScan.from_card(door, input, hosts, kind, override, now)
      end)

    {:noreply, socket}
  end

  # A member's button submits the whole form, so the pick carries the time box as it
  # shows (#168). Enter in the search box submits with no member: a card's link or code
  # records that card, as a plug-in barcode scanner types it (#484); anything else only
  # searches.
  def handle_event("pick", %{"pick" => member_id} = params, socket) do
    kind = socket.assigns.kind
    override = params["override"] || ""

    socket =
      socket
      |> assign(override: override)
      |> record(&RecordAttendanceScan.from_name(&1, member_id, kind, override, &2))
      |> assign(search: "", matches: [])

    {:noreply, socket}
  end

  def handle_event("pick", params, socket) do
    input = String.trim(params["search"] || "")

    if card_entry?(input) do
      kind = socket.assigns.kind
      override = params["override"] || ""
      hosts = Web.VerifyHost.trusted_hosts()

      socket =
        socket
        |> assign(override: override, search: "", matches: [])
        |> record(&RecordAttendanceScan.from_card(&1, input, hosts, kind, override, &2))
        |> push_event("clear-search", %{})

      {:noreply, socket}
    else
      handle_event("change", params, socket)
    end
  end

  def handle_event("undo", %{"id" => scan_id}, socket) do
    socket =
      with_open_door(socket, fn socket, now ->
        case socket |> door() |> RecordAttendanceScan.undo(scan_id, now) do
          :ok -> assign(socket, message: {:info, "Scan removed."})
          # Closed between the check and the undo.
          {:error, _reason} -> assign_closed(socket, now)
        end
      end)

    {:noreply, socket}
  end

  def handle_event("toggle_yet_to_arrive", _params, socket),
    do: {:noreply, update(socket, :show_yet_to_arrive, &(!&1))}

  def handle_event("scan_failed", _params, socket),
    do: {:noreply, assign(socket, :scan_failed, true)}

  defp record(socket, record) do
    with_open_door(socket, fn socket, now ->
      {kind, _text} = message = socket |> door() |> record.(now) |> message(socket.assigns.team)

      if kind in [:arrived, :left],
        do: Process.send_after(self(), {:clear_message, message}, @confirm_ms)

      socket
      |> assign(message: message)
      |> push_event("scan-sound", %{sound: kind})
    end)
  end

  # Runs `action` with the socket read again, while the door may take attendance. A team
  # admin viewing as a member never gets here: Web.UserAuth refuses their scans (#440).
  defp with_open_door(socket, action) do
    now = DateTime.utc_now()
    socket = reload(socket, now)

    cond do
      Activity.deleted?(socket.assigns.activity) -> socket
      socket.assigns.closed -> assign(socket, message: nil)
      true -> action.(socket, now)
    end
  end

  # Reads the activity again, so a new time or title shows, and one deleted since the page
  # opened leaves it.
  defp reload(socket, now) do
    activity = socket.assigns.activity |> Repo.reload!() |> Repo.preload(:team)
    socket = assign(socket, activity: activity, team: activity.team)

    if Activity.deleted?(activity),
      do: Web.ActivityLive.leave_deleted(socket, activity),
      else: assign_closed(socket, now)
  end

  # Another activity is taking attendance, so whoever holds the iPad can switch to it:
  # one that overlaps, or tonight's when this page is still on last week's.
  defp others_now?(activity, now) do
    activity.team
    |> Activity.taking_attendance_now(now)
    |> Enum.any?(&(&1.id != activity.id))
  end

  # `{kind, text}`: `:arrived` or `:left` for a good scan, `:error`, or `:info`. The kind
  # picks the banner's colour and the scan's sound.
  defp message({:ok, scan}, team) do
    time = scan |> AttendanceScan.time() |> Service.Format.time_short(team.timezone)

    case scan.kind do
      "arrived" -> {:arrived, "#{scan.member.name} arrived at #{time}."}
      "left" -> {:left, "#{scan.member.name} left at #{time}."}
    end
  end

  defp message({:error, reason}, _team), do: {:error, error_text(reason)}

  defp error_text(:not_found), do: "No ID card has this code. Find the member by name instead."
  defp error_text(:other_site), do: "This is not a SAR Duty ID card. Find the member by name."
  defp error_text(:other_team), do: "This ID card is for another team."
  defp error_text(:revoked), do: "This ID card is cancelled. Find the member by name instead."
  defp error_text(:left_team), do: "This member is retired."
  defp error_text(:bad_time), do: "Enter the time as hours and minutes, like 09:30."

  # Signed up is read again with the scans, so the 10-minute sync's changes show too.
  defp load_scans(socket) do
    activity = socket.assigns.activity
    all_scans = AttendanceScan.get_all(activity)
    yet_to_arrive = activity |> Attendance.signed_up_members() |> BuildYetToArrive.call(all_scans)
    scans = all_scans |> Enum.reverse() |> Enum.take(@recent_count)
    assign(socket, scans: scans, yet_to_arrive: yet_to_arrive)
  end

  @doc "Current members whose name contains every word typed, up to #{@max_name_matches}."
  def matches(_members, search) when byte_size(search) < 2, do: []

  def matches(members, search) do
    words = search |> String.downcase() |> String.split()

    members
    |> Enum.filter(fn member ->
      name = String.downcase(member.name)
      Enum.all?(words, &String.contains?(name, &1))
    end)
    |> Enum.sort_by(& &1.name)
    |> Enum.take(@max_name_matches)
  end

  @doc """
  Whether text in the name box is a card's link or code rather than a name. A printed
  code has a dash and almost every code has a digit; names have neither.
  """
  def card_entry?(text) do
    String.contains?(text, "://") or
      (MemberCard.normalize_code(text) != nil and String.match?(text, ~r/[\d-]/))
  end

  # As card_entry?/1, but also true while a scanner is still typing a link, so the name
  # search doesn't say "no member" at each character.
  defp card_text?(text) do
    text = text |> String.trim() |> String.downcase()
    String.starts_with?(text, "ht") or card_entry?(text)
  end

  attr :message, :any, required: true

  # Big and coloured, so the person at the door sees each scan land at a glance.
  defp message(%{message: {:info, text}} = assigns) do
    assigns = assign(assigns, :text, text)

    ~H"""
    <p id="message" role="status" class="mt-4 mb-0 font-semibold">{@text}</p>
    """
  end

  defp message(%{message: {kind, text}} = assigns) do
    assigns = assign(assigns, kind: kind, text: text)

    ~H"""
    <.band
      id="message"
      role="status"
      kind={message_kind(@kind)}
      icon={message_icon(@kind)}
      title={@text}
      class="mt-4"
    />
    """
  end

  defp message_kind(:arrived), do: :success
  defp message_kind(:left), do: :info
  defp message_kind(:error), do: :danger

  defp message_icon(:arrived), do: "log-in"
  defp message_icon(:left), do: "log-out"
  defp message_icon(:error), do: "circle-alert"

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@team}/activities"} />
      <:item label={"#{@activity.ref_id}"} path={~p"/teams/#{@team}/activities/#{@activity.id}"} />
      <:item label="Take attendance" />
    </.breadcrumbs>
    <h1 class="title mb-1">{@activity.title}</h1>
    <p id="activity-summary" class="text-text-muted">
      {when_text(@activity, @team)}<span :if={@activity.address}> · {@activity.address}</span>
    </p>
    <p :if={@others_now?} class="action">
      <.a id="other-activities" navigate={~p"/teams/#{@team}/take-attendance"}>Other activities now</.a>
    </p>

    <p :if={@closed} id="closed" class="mt-4 font-semibold">
      {closed_text(@closed, @activity, @team)}
    </p>
    <div :if={!@closed} id="controls">
      <div :if={@yet_to_arrive.signed_up > 0} class="mt-4">
        <.button
          id="toggle-yet-to-arrive"
          type="button"
          aria-expanded={to_string(@show_yet_to_arrive)}
          aria-controls="yet-to-arrive"
          phx-click="toggle_yet_to_arrive"
        >
          Yet to arrive · {count_text(@yet_to_arrive)}
        </.button>
        <.yet_to_arrive_list
          :if={@show_yet_to_arrive}
          yet_to_arrive={@yet_to_arrive}
          contacts?={@team_admin?}
          class="mt-2"
        />
      </div>

      <div id="kind" class="mt-4 flex gap-2" role="group" aria-label="Members are">
        <.button
          :for={{kind, label} <- [{"arrived", "Arriving"}, {"left", "Leaving"}]}
          id={"kind-#{kind}"}
          type="button"
          variant={if @kind == kind, do: :primary, else: :default}
          class="flex-1"
          aria-pressed={to_string(@kind == kind)}
          phx-click="set_kind"
          phx-value-kind={kind}
          data-return-focus
        >
          {label}
        </.button>
      </div>

      <form id="door-form" phx-change="change" phx-submit="pick">
        <div class="mt-4">
          <.input type="time" id="override" name="override" value={@override} label="Time (optional)">
            Leave this empty to use the time of each scan. Set it to catch up from a paper list.
          </.input>
          <p :if={@override != ""} id="override-note" class="-mt-4 font-semibold">
            Recording as {@override} ·
            <.a id="clear-override" href="#" phx-click="clear_override">Clear time</.a>
          </p>
        </div>

        <.message :if={@message} message={@message} />

        <.qr_scanner
          label="Scan ID cards"
          variant={:success}
          data-continuous
          data-override-input="override"
          class="mt-4"
        />
        <p :if={@scan_failed} id="scan-failed" class="text-danger-text">
          The camera did not start. Allow camera access, or find members by name.
        </p>

        <div class="mt-4">
          <.input
            type="search"
            id="search"
            name="search"
            value={@search}
            label="Find a member by name"
            autocomplete="off"
            phx-debounce="150"
            phx-hook="ScannerInput"
          >
            Or scan an ID card with a plug-in barcode scanner.
          </.input>
        </div>
        <ul :if={@matches != []} id="matches" class="-mt-4">
          <li :for={member <- @matches} class="flex items-center justify-between gap-2 py-1">
            <span>{member.name}</span>
            <.button id={"pick-#{member.id}"} type="submit" name="pick" value={member.id}>
              {if @kind == "arrived", do: "Record arrival", else: "Record departure"}
            </.button>
          </li>
        </ul>
        <p
          :if={@matches == [] and String.length(@search) >= 2 and not card_text?(@search)}
          id="no-matches"
          class="-mt-4"
        >
          No current member has that name.
        </p>
      </form>

      <h2 class="heading mt-4">Recorded</h2>
      <p :if={@scans == []} id="no-scans">Nobody yet. Scans show here as you take them.</p>
      <.table :if={@scans != []} id="scans" rows={@scans} class="table-striped">
        <:col :let={scan} label="Name">{scan.member.name}</:col>
        <:col :let={scan} label="Scan" class="whitespace-nowrap">
          {if scan.kind == "arrived", do: "Arrived", else: "Left"} {Service.Format.time_short(
            AttendanceScan.time(scan),
            @team.timezone
          )}
        </:col>
        <:col :let={scan} label="" class="w-px">
          <.button
            id={"undo-#{scan.id}"}
            type="button"
            size={:sm}
            variant={:link}
            phx-click="undo"
            phx-value-id={scan.id}
          >
            Undo
          </.button>
        </:col>
      </.table>
    </div>

    <p :if={@team_admin?} class="action mt-8">
      <.a
        id="send-attendance"
        navigate={~p"/teams/#{@team}/activities/#{@activity.id}/attendance"}
      >Send attendance</.a>
    </p>
    """
  end

  defp when_text(activity, team) do
    "#{Service.Format.day_coming_up(activity.started_at, DateTime.utc_now(), team.timezone)} " <>
      "#{Service.Format.time_short(activity.started_at, team.timezone)}–" <>
      Service.Format.time_short(activity.finished_at, team.timezone)
  end

  # Only a member's window closes; a team admin takes attendance at any time.
  defp closed_text(:not_yet, activity, team) do
    {opens_at, _closes_at} = Activity.attendance_window(activity)

    "You can take attendance from #{window_time(opens_at, team)}, " <>
      "#{window_hours()} before it starts."
  end

  defp closed_text(:closed, activity, team) do
    {_opens_at, closes_at} = Activity.attendance_window(activity)

    "Taking attendance closed at #{window_time(closes_at, team)}. " <>
      "Ask a team admin to add anyone missing."
  end

  defp window_hours, do: Service.Format.duration(Activity.attendance_window_hours() * 60)

  # The time alone today, and with its day otherwise.
  defp window_time(at, team) do
    now = DateTime.utc_now()

    if Service.Format.day_coming_up(at, now, team.timezone) == "Today",
      do: Service.Format.time_short(at, team.timezone),
      else: Service.Format.month_day_time(at, team.timezone)
  end
end
