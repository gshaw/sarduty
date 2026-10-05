defmodule Web.AttendanceLinkLive do
  use Web, :live_view_narrow_layout

  import Web.Components.Table

  alias App.Model.AttendanceLink
  alias App.Model.AttendanceScan
  alias App.Model.Member
  alias App.Operation.RecordAttendanceScan

  # The door's page for taking attendance: no login, only the link's token. It shows the
  # activity, records ID card scans and members picked by name, and lists what it has
  # recorded so a mistake can be undone. The link is looked up again for every action,
  # so closing it stops the page at once.
  @max_name_matches 8
  @recent_count 30

  def mount(%{"token" => token}, _session, socket) do
    now = DateTime.utc_now()
    link = AttendanceLink.find_by_token(token)

    if link && AttendanceLink.open?(link, now) do
      if connected?(socket),
        do: Phoenix.PubSub.subscribe(App.PubSub, AttendanceScan.topic(link.activity_id))

      members =
        link.team_id
        |> Member.get_all()
        |> Enum.filter(&Member.current?(&1, now))

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
          scan_failed: false
        )
        |> load_scans()

      {:ok, socket}
    else
      {:ok, assign(socket, page_title: "Attendance link closed", link: nil)}
    end
  end

  def handle_info(:attendance_scans_changed, socket), do: {:noreply, load_scans(socket)}

  def handle_event("set_kind", %{"kind" => kind}, socket) when kind in ["arrived", "left"],
    do: {:noreply, assign(socket, kind: kind, message: nil)}

  def handle_event("set_override", %{"override" => override}, socket),
    do: {:noreply, assign(socket, override: override)}

  def handle_event("search", %{"search" => search}, socket),
    do:
      {:noreply, assign(socket, search: search, matches: matches(socket.assigns.members, search))}

  def handle_event("scanned", %{"code" => input}, socket) do
    %{kind: kind, override: override} = socket.assigns
    hosts = Web.VerifyHost.trusted_hosts()

    socket =
      record(socket, fn link, now ->
        RecordAttendanceScan.from_card(link, input, hosts, kind, override, now)
      end)

    {:noreply, socket}
  end

  def handle_event("pick", %{"id" => member_id}, socket) do
    %{kind: kind, override: override} = socket.assigns

    socket =
      socket
      |> record(&RecordAttendanceScan.from_name(&1, member_id, kind, override, &2))
      |> assign(search: "", matches: [])

    {:noreply, socket}
  end

  def handle_event("undo", %{"id" => scan_id}, socket) do
    AttendanceScan.delete(socket.assigns.activity, scan_id)
    {:noreply, assign(socket, message: {:info, "Scan removed."})}
  end

  def handle_event("scan_failed", _params, socket),
    do: {:noreply, assign(socket, :scan_failed, true)}

  defp record(socket, record) do
    now = DateTime.utc_now()
    link = AttendanceLink.find_by_token(socket.assigns.token)

    if link && AttendanceLink.open?(link, now),
      do: assign(socket, message: message(record.(link, now), socket.assigns.team)),
      else: assign(socket, page_title: "Attendance link closed", link: nil)
  end

  defp message({:ok, scan}, team) do
    time = scan |> AttendanceScan.time() |> Service.Format.time_short(team.timezone)
    verb = if scan.kind == "arrived", do: "arrived", else: "left"
    {:ok, "#{scan.member.name} #{verb} at #{time}."}
  end

  defp message({:error, reason}, _team), do: {:error, error_text(reason)}

  defp error_text(:not_found), do: "No ID card has this code. Find the member by name instead."
  defp error_text(:other_site), do: "This is not a SAR Duty ID card. Find the member by name."
  defp error_text(:other_team), do: "This ID card is for another team."
  defp error_text(:revoked), do: "This ID card is cancelled. Find the member by name instead."
  defp error_text(:left_team), do: "This member has left the team."
  defp error_text(:bad_time), do: "Enter the time as hours and minutes, like 09:30."
  defp error_text(:closed), do: "This attendance link is closed."

  defp load_scans(socket) do
    scans =
      socket.assigns.activity
      |> AttendanceScan.get_all()
      |> Enum.reverse()
      |> Enum.take(@recent_count)

    assign(socket, scans: scans)
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

  def render(%{link: nil} = assigns) do
    ~H"""
    <div id="link-closed">
      <h1 class="title">Attendance link closed</h1>
      <p>This link no longer takes attendance. Ask a team admin for a new link.</p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <h1 class="title mb-0">Take attendance</h1>
    <p id="activity-summary" class="mt-1 text-secondary-1">
      <b class="text-base-content">{@activity.title}</b>
      · {@team.name} · {Service.Format.month_day_time(@activity.started_at, @team.timezone)}–{Service.Format.time_short(
        @activity.finished_at,
        @team.timezone
      )}
    </p>

    <div id="kind" class="mt-p flex gap-2" role="group" aria-label="Members are">
      <.button
        :for={{kind, label} <- [{"arrived", "Arriving"}, {"left", "Leaving"}]}
        id={"kind-#{kind}"}
        type="button"
        variant={if @kind == kind, do: :primary, else: :default}
        class="flex-1 justify-center"
        aria-pressed={to_string(@kind == kind)}
        phx-click="set_kind"
        phx-value-kind={kind}
      >
        {label}
      </.button>
    </div>

    <p
      :if={@message}
      id="message"
      role="status"
      class={[
        "mt-p mb-0 font-semibold",
        elem(@message, 0) == :error && "text-danger-1",
        elem(@message, 0) == :ok && "text-success-1"
      ]}
    >
      {elem(@message, 1)}
    </p>

    <div
      id="scanner"
      phx-hook="QRScanner"
      phx-update="ignore"
      data-continuous
      class="group mt-p"
    >
      <video class="hidden group-data-scanning:block w-full rounded" playsinline muted></video>
      <div class="group-data-scanning:hidden">
        <.button
          type="button"
          variant={:success}
          size={:lg}
          class="w-full justify-center"
          data-scan-start
        >
          Scan ID cards
        </.button>
      </div>
      <div class="hidden group-data-scanning:block mt-2">
        <.button type="button" class="w-full justify-center" data-scan-stop>Stop scanning</.button>
      </div>
    </div>
    <p :if={@scan_failed} id="scan-failed" class="text-danger-1">
      The camera did not start. Allow camera access, or find members by name.
    </p>

    <form id="search-form" phx-change="search" phx-submit="search" class="mt-p">
      <.input
        type="search"
        name="search"
        value={@search}
        label="Find a member by name"
        autocomplete="off"
        phx-debounce="150"
      >
        For a member without their ID card.
      </.input>
    </form>
    <ul :if={@matches != []} id="matches" class="mt-2">
      <li :for={member <- @matches} class="flex items-center justify-between gap-2 py-1">
        <span>{member.name}</span>
        <.button
          id={"pick-#{member.id}"}
          type="button"
          size={:sm}
          phx-click="pick"
          phx-value-id={member.id}
        >
          {if @kind == "arrived", do: "Record arrival", else: "Record departure"}
        </.button>
      </li>
    </ul>
    <p :if={@matches == [] and String.length(@search) >= 2} id="no-matches" class="mt-2">
      No current member has that name.
    </p>

    <form id="override-form" phx-change="set_override" class="mt-p">
      <.input type="time" name="override" value={@override} label="Time (optional)">
        Leave this empty to use the time of each scan. Set it to catch up from a paper list.
      </.input>
    </form>

    <h2 class="heading mt-p">Recorded</h2>
    <p :if={@scans == []} id="no-scans">Nobody yet. Scans show here as you take them.</p>
    <.table :if={@scans != []} id="scans" rows={@scans} class="table-striped">
      <:col :let={scan} label="Name">{scan.member.name}</:col>
      <:col :let={scan} label="Scan" class="whitespace-nowrap tabular-nums">
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
