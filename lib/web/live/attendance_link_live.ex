defmodule Web.AttendanceLinkLive do
  use Web, :live_view_narrow_layout

  import Web.Components.Scanner
  import Web.Components.YetToArrive

  alias App.Model.Attendance
  alias App.Model.AttendanceLink
  alias App.Model.AttendanceScan
  alias App.Model.Member
  alias App.Operation.BuildYetToArrive
  alias App.Operation.RecordAttendanceScan

  # The door's page for taking attendance: no login, only the link's token. It shows the
  # activity, records ID card scans and members picked by name, and lists what it has
  # recorded so a mistake can be undone. The link is looked up again for every action,
  # so closing it stops the page at once.
  @max_name_matches 8
  @recent_count 30
  # A good scan's confirmation shows this long, then the page is ready for the next.
  @confirm_ms 3000

  def mount(%{"token" => token}, _session, socket) do
    now = DateTime.utc_now()
    link = AttendanceLink.find_by_token(token)

    if link && AttendanceLink.open?(link, now) do
      if connected?(socket),
        do: Phoenix.PubSub.subscribe(App.PubSub, AttendanceScan.topic(link.activity_id))

      members =
        link.team_id
        |> Member.get_all()
        |> Enum.filter(&(Member.current?(&1, now) and not &1.not_a_person))

      socket =
        socket
        |> assign(
          page_title: "Take attendance",
          token: token,
          link: link,
          activity: link.activity,
          team: link.activity.team,
          members: members,
          kind: "arrived",
          override: "",
          search: "",
          matches: [],
          message: nil,
          scan_failed: false,
          show_yet_to_arrive: false
        )
        |> load_scans()

      {:ok, socket}
    else
      {:ok, assign(socket, page_title: "Attendance link closed", link: nil)}
    end
  end

  def handle_info(:attendance_scans_changed, socket), do: {:noreply, load_scans(socket)}

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
       matches: matches(socket.assigns.members, search)
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
      record(socket, fn link, now ->
        RecordAttendanceScan.from_card(link, input, hosts, kind, override, now)
      end)

    {:noreply, socket}
  end

  # A member's button submits the whole form, so the pick carries the time box as it
  # shows (#168). Enter in the search box submits with no member and only searches.
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

  def handle_event("pick", params, socket), do: handle_event("change", params, socket)

  def handle_event("undo", %{"id" => scan_id}, socket) do
    socket =
      with_open_link(socket, fn link, now ->
        case RecordAttendanceScan.undo(link, scan_id, now) do
          :ok -> assign(socket, message: {:info, "Scan removed."})
          {:error, reason} -> assign(socket, message: {:error, error_text(reason)})
        end
      end)

    {:noreply, socket}
  end

  def handle_event("toggle_yet_to_arrive", _params, socket),
    do: {:noreply, update(socket, :show_yet_to_arrive, &(!&1))}

  def handle_event("scan_failed", _params, socket),
    do: {:noreply, assign(socket, :scan_failed, true)}

  defp record(socket, record) do
    with_open_link(socket, fn link, now ->
      {kind, _text} = message = message(record.(link, now), socket.assigns.team)

      if kind in [:arrived, :left],
        do: Process.send_after(self(), {:clear_message, message}, @confirm_ms)

      socket
      |> assign(message: message)
      |> push_event("scan-sound", %{sound: kind})
    end)
  end

  # Looks the link up again, so a link closed since the page opened stops it at once.
  defp with_open_link(socket, action) do
    now = DateTime.utc_now()
    link = AttendanceLink.find_by_token(socket.assigns.token)

    if link && AttendanceLink.open?(link, now),
      do: action.(link, now),
      else: assign(socket, page_title: "Attendance link closed", link: nil)
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
  defp error_text(:left_team), do: "This member has left the team."
  defp error_text(:bad_time), do: "Enter the time as hours and minutes, like 09:30."
  defp error_text(:closed), do: "This attendance link is closed."

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

  defp message_icon(:arrived), do: "hero-arrow-right-end-on-rectangle"
  defp message_icon(:left), do: "hero-arrow-left-start-on-rectangle"
  defp message_icon(:error), do: "hero-exclamation-circle"

  def render(%{link: nil} = assigns) do
    ~H"""
    <div id="link-closed">
      <h1 class="title">Attendance link closed</h1>
      <p>This attendance link is closed. Ask a team admin for a new link.</p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <h1 class="title mb-1">Take attendance</h1>
    <p id="activity-summary" class="text-text-muted">
      <b class="text-text">{@activity.title}</b>
      · {@team.name} · {Service.Format.month_day_time(@activity.started_at, @team.timezone)}–{Service.Format.time_short(
        @activity.finished_at,
        @team.timezone
      )}
    </p>

    <div :if={@yet_to_arrive.signed_up > 0} class="mt-4">
      <.button
        id="toggle-yet-to-arrive"
        type="button"
        size={:sm}
        aria-expanded={to_string(@show_yet_to_arrive)}
        aria-controls="yet-to-arrive"
        phx-click="toggle_yet_to_arrive"
      >
        Yet to arrive · {count_text(@yet_to_arrive)}
      </.button>
      <.yet_to_arrive_list
        :if={@show_yet_to_arrive}
        yet_to_arrive={@yet_to_arrive}
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
        >
          For a member without their ID card.
        </.input>
      </div>
      <ul :if={@matches != []} id="matches" class="-mt-4">
        <li :for={member <- @matches} class="flex items-center justify-between gap-2 py-1">
          <span>{member.name}</span>
          <.button id={"pick-#{member.id}"} type="submit" name="pick" value={member.id} size={:sm}>
            {if @kind == "arrived", do: "Record arrival", else: "Record departure"}
          </.button>
        </li>
      </ul>
      <p :if={@matches == [] and String.length(@search) >= 2} id="no-matches" class="-mt-4">
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
    """
  end
end
