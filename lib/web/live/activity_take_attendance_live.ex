defmodule Web.ActivityTakeAttendanceLive do
  use Web, :live_view_app_layout

  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.AttendanceScan
  alias App.Operation.BuildAttendanceTimes
  alias App.Operation.CloseAttendanceLink
  alias App.Operation.CreateAttendanceLink
  alias App.Repo

  # The team admin's side of taking attendance at the door: make or close the link, and
  # watch arrivals and departures come in.
  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    activity = team |> Activity.find!(params["id"]) |> Repo.preload(:team)

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(App.PubSub, AttendanceScan.topic(activity.id))

    socket =
      socket
      |> assign(page_title: "Take attendance", activity: activity)
      |> load_link()
      |> load_times()

    {:noreply, socket}
  end

  def handle_info(:attendance_scans_changed, socket), do: {:noreply, load_times(socket)}

  def handle_event("create-link", _params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns
    CreateAttendanceLink.call(team, activity, user, DateTime.utc_now())
    {:noreply, socket |> load_link() |> put_flash(:info, "Attendance link made.")}
  end

  def handle_event("close-link", _params, socket) do
    %{current_team: team, activity: activity} = socket.assigns
    CloseAttendanceLink.call(team, activity, DateTime.utc_now())
    {:noreply, socket |> load_link() |> put_flash(:info, "Attendance link closed.")}
  end

  defp load_link(socket) do
    %{current_team: team, activity: activity} = socket.assigns
    link = AttendanceLink.find_current(team, activity)
    link = if link && AttendanceLink.open?(link, DateTime.utc_now()), do: link
    assign(socket, link: link)
  end

  defp load_times(socket) do
    activity = socket.assigns.activity
    assign(socket, times: BuildAttendanceTimes.call(activity, AttendanceScan.get_all(activity)))
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Activities" path={~p"/#{@current_team.subdomain}/activities"} />
      <:item
        label={"#{@activity.ref_id}"}
        path={~p"/#{@current_team.subdomain}/activities/#{@activity.id}"}
      />
      <:item label="Take attendance" />
    </.breadcrumbs>
    <h1 class="title">{@activity.title}</h1>

    <h2 class="heading">Attendance link</h2>
    <.link_section link={@link} activity={@activity} />

    <h2 class="heading mt-p">Arrivals and departures</h2>
    <.times_section times={@times} activity={@activity} />
    """
  end

  attr :link, :any, required: true
  attr :activity, :any, required: true

  defp link_section(%{link: nil} = assigns) do
    ~H"""
    <div id="no-link">
      <p>
        Make a link for the person taking attendance at the door. They open it on a phone and
        scan each member's ID card as they arrive and leave. They do not need an account.
      </p>
      <p>
        The link works until {Service.Format.datetime_medium(
          AttendanceLink.expires_at(@activity),
          @activity.team.timezone
        )}, a day after the activity ends. Anyone with it sees your members' names.
      </p>
      <.button id="create-link" variant={:success} phx-click="create-link">
        Make attendance link
      </.button>
    </div>
    """
  end

  defp link_section(assigns) do
    ~H"""
    <div id="open-link">
      <p>
        Send this link to the person taking attendance at the door. It works until {Service.Format.datetime_medium(
          AttendanceLink.expires_at(@activity),
          @activity.team.timezone
        )}.
      </p>
      <div class="flex gap-2 items-center">
        <input
          id="attendance-link-url"
          type="text"
          readonly
          value={url(~p"/attendance/#{@link.token}")}
          class="input w-full font-mono text-sm"
        />
        <.button
          id="copy-link"
          type="button"
          phx-click={JS.dispatch("sarduty:copy", to: "#attendance-link-url")}
        >
          Copy link
        </.button>
      </div>
      <.form_actions class="mt-p05">
        <.button
          id="create-link"
          phx-click="create-link"
          data-confirm="Make a new link? This link stops working."
        >
          Make new link
        </.button>
        <.button
          id="close-link"
          variant={:danger}
          phx-click="close-link"
          data-confirm="Close this link? It stops taking attendance."
        >
          Close link
        </.button>
      </.form_actions>
    </div>
    """
  end

  attr :times, :list, required: true
  attr :activity, :any, required: true

  defp times_section(%{times: []} = assigns) do
    ~H"""
    <p id="no-times">
      Nobody has arrived yet. Members show here as the attendance link records them.
    </p>
    """
  end

  defp times_section(assigns) do
    ~H"""
    <p>
      {Service.Format.count(length(@times), one: "%d member", many: "%d members")}. SAR Duty uses
      the start time for anyone who arrives up to {BuildAttendanceTimes.grace_minutes()} minutes
      early, and the end time for anyone who leaves up to {BuildAttendanceTimes.grace_minutes()} minutes late.
    </p>
    <.table id="times" rows={@times} class="table-striped w-fit">
      <:col :let={row} label="Name">{row.member.name}</:col>
      <:col :let={row} label="Arrived" align="right" class="tabular-nums">
        {Service.Format.time_short(row.arrived_at, @activity.team.timezone)}
      </:col>
      <:col :let={row} label="Left" align="right" class="tabular-nums">
        {Service.Format.time_short(row.left_at, @activity.team.timezone)}
      </:col>
      <:col :let={row} label="Notes">
        <span :for={note <- row.notes} class={["block", note_class(note)]}>{note_text(note)}</span>
      </:col>
    </.table>
    """
  end

  defp note_class(:left_before_arriving), do: "text-danger-1"
  defp note_class(_note), do: "text-secondary-1"

  defp note_text(:no_arrival), do: "No arrival scan. Uses the start time."
  defp note_text(:no_departure), do: "No departure scan. Uses the end time."
  defp note_text(:left_before_arriving), do: "Left before arriving. Fix the times at the door."
end
