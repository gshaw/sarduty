defmodule Web.ActivityTakeAttendanceLive do
  use Web, :live_view_app_layout

  import Web.Components.YetToArrive

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.AttendanceLink
  alias App.Model.AttendanceScan
  alias App.Model.NoShow
  alias App.Model.ShortLink
  alias App.Operation.BuildAttendanceTimes
  alias App.Operation.BuildYetToArrive
  alias App.Operation.CloseAttendanceLink
  alias App.Operation.CreateAttendanceLink
  alias App.Operation.FollowUpNoShow
  alias App.Operation.SendAttendanceToD4H
  alias App.Repo

  # The team admin's side of taking attendance at the door: make or close the link, and
  # watch arrivals and departures come in.
  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    activity = team |> Activity.find!(params["id"]) |> Repo.preload(:team)

    if Activity.deleted?(activity),
      do: {:noreply, Web.ActivityLive.leave_deleted(socket, activity)},
      else: load(socket, activity)
  end

  defp load(socket, activity) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(App.PubSub, AttendanceScan.topic(activity.id))

    socket =
      socket
      |> assign(page_title: "Take attendance", activity: activity)
      |> assign(review: nil, selected: MapSet.new(), failures: [])
      |> load_link()
      |> load_times()
      |> load_no_shows()

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

  # Reads D4H live, like the import attendance page, so the plan matches D4H now.
  def handle_event("review", _params, socket) do
    %{current_team: team, activity: activity} = socket.assigns

    case SendAttendanceToD4H.preview(team, activity) do
      {:ok, review} ->
        selected =
          for change <- review.changes, change.selected, into: MapSet.new(), do: change.key

        {:noreply, assign(socket, review: review, selected: selected, failures: [])}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  # `done` is the state the click asks for, since a checkbox's click carries no state.
  def handle_event("follow-up", %{"id" => id, "done" => done}, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    FollowUpNoShow.call(team, id, done == "true", user, DateTime.utc_now())
    {:noreply, load_no_shows(socket)}
  end

  def handle_event("select", params, socket),
    do: {:noreply, assign(socket, :selected, MapSet.new(params["keys"] || []))}

  def handle_event("cancel-review", _params, socket),
    do: {:noreply, assign(socket, review: nil, selected: MapSet.new())}

  def handle_event("send", params, socket) do
    %{current_team: team, activity: activity} = socket.assigns
    keys = params["keys"] || []

    case SendAttendanceToD4H.call(
           team,
           activity,
           socket.assigns.current_user,
           keys,
           DateTime.utc_now()
         ) do
      {:ok, results} -> {:noreply, show_results(socket, results)}
      {:error, error} -> {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  defp show_results(socket, results) do
    failures = for {change, {:error, message}} <- results, do: {change, message}
    saved = length(results) - length(failures)
    kind = if failures == [], do: :info, else: :error

    socket
    |> assign(review: nil, selected: MapSet.new(), failures: failures)
    |> load_link()
    |> load_no_shows()
    |> put_flash(kind, sent_text(saved, length(failures)))
  end

  defp sent_text(saved, 0), do: "#{count_changes(saved)} saved to D4H."
  defp sent_text(0, failed), do: "#{count_changes(failed)} did not go through."

  defp sent_text(saved, failed),
    do: "#{count_changes(saved)} saved to D4H. #{count_changes(failed)} did not go through."

  defp count_changes(n),
    do: Service.Format.count(n, one: "%d attendance change", many: "%d attendance changes")

  defp error_text(:published),
    do: "Attendance cannot be changed once the activity is published. Unpublish it in D4H first."

  defp error_text(:deleted), do: "This activity is deleted in D4H. Nothing can be sent to it."

  defp error_text(:no_team_key), do: "Save the team's D4H access key in Team settings first."

  defp error_text(%D4H.Error{status: status} = error) when status in [400, 404],
    do:
      "D4H cannot find this activity. It may have been deleted or changed in D4H. #{Exception.message(error)}"

  defp error_text(error), do: "D4H did not answer. Try again. #{Exception.message(error)}"

  defp load_link(socket) do
    %{current_team: team, activity: activity} = socket.assigns
    link = AttendanceLink.find_current(team, activity)
    link = if link && AttendanceLink.open?(link, DateTime.utc_now()), do: link
    assign(socket, link: link)
  end

  defp load_no_shows(socket),
    do: assign(socket, no_shows: NoShow.get_all(socket.assigns.activity))

  defp load_times(socket) do
    activity = socket.assigns.activity
    scans = AttendanceScan.get_all(activity)

    assign(socket,
      times: BuildAttendanceTimes.call(activity, scans),
      yet_to_arrive: activity |> Attendance.signed_up_members() |> BuildYetToArrive.call(scans)
    )
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        label={"#{@activity.ref_id}"}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label="Take attendance" />
    </.breadcrumbs>
    <h1 class="title">{@activity.title}</h1>

    <h2 class="heading">Attendance link</h2>
    <.link_section link={@link} activity={@activity} />

    <h2 class="heading mt-4">Arrivals and departures</h2>
    <.times_section times={@times} activity={@activity} />

    <div :if={@yet_to_arrive.signed_up > 0} id="yet-to-arrive-section">
      <h2 class="heading mt-4">Yet to arrive · {count_text(@yet_to_arrive)}</h2>
      <p>
        Members D4H shows as signed up who have not arrived. Call or text to check whether
        they're still coming.
      </p>
      <.yet_to_arrive_list yet_to_arrive={@yet_to_arrive} class="md:max-w-xl" />
    </div>

    <h2 class="heading mt-4">Send to D4H</h2>
    <.failures_section failures={@failures} />
    <.send_section review={@review} selected={@selected} times={@times} activity={@activity} />

    <div :if={@no_shows != []} id="no-shows">
      <h2 class="heading mt-4">No-shows</h2>
      <.no_shows_section no_shows={@no_shows} activity={@activity} />
    </div>
    """
  end

  attr :no_shows, :list, required: true
  attr :activity, :any, required: true

  defp no_shows_section(assigns) do
    ~H"""
    <p>
      These members signed up and did not arrive. Check that each one is OK, then mark them
      followed up.
    </p>
    <.table
      id="no-show-list"
      rows={@no_shows}
      row_id={&"no-show-#{&1.id}"}
      class="table-striped table-stack md:w-fit"
    >
      <:col :let={no_show} label="Name" class="stack-title">{no_show.member.name}</:col>
      <:col :let={no_show} label="Phone" class="whitespace-nowrap stack-optional">
        <.a :if={no_show.member.phone} href={"tel:#{no_show.member.phone}"}>
          {no_show.member.phone}
        </.a>
      </:col>
      <:col :let={no_show} label="Email" class="stack-full stack-optional break-all">
        <.a :if={no_show.member.email} href={"mailto:#{no_show.member.email}"}>
          {no_show.member.email}
        </.a>
      </:col>
      <:col :let={no_show} label="Followed up" class="stack-full">
        <label class="flex items-center gap-2 whitespace-nowrap min-h-6">
          <input
            type="checkbox"
            id={"follow-up-#{no_show.id}"}
            phx-click="follow-up"
            phx-value-id={no_show.id}
            phx-value-done={to_string(no_show.followed_up_at == nil)}
            checked={no_show.followed_up_at != nil}
          />
          <span :if={no_show.followed_up_at} class="hint">
            {Service.Format.month_day_time(no_show.followed_up_at, @activity.team.timezone)}
          </span>
        </label>
      </:col>
    </.table>
    """
  end

  attr :failures, :list, required: true

  defp failures_section(assigns) do
    ~H"""
    <div :if={@failures != []} id="failures" class="mb-4">
      <p class="text-danger-text font-semibold">These changes did not go through:</p>
      <ul>
        <li :for={{change, message} <- @failures}>{change.member.name}: {message}</li>
      </ul>
    </div>
    """
  end

  attr :review, :any, required: true
  attr :selected, :any, required: true
  attr :times, :list, required: true
  attr :activity, :any, required: true

  defp send_section(%{review: nil} = assigns) do
    ~H"""
    <div id="send-start">
      <p>
        Review the changes before SAR Duty makes them. Members who arrived are marked attending
        with their times. Members who signed up but did not arrive are marked absent.
        When every change goes through, SAR Duty closes the attendance link.
      </p>
      <.button id="review" variant={:primary} phx-click="review" phx-disable-with="Reading D4H…">
        Review changes
      </.button>
    </div>
    """
  end

  defp send_section(%{review: %{published: true}} = assigns) do
    ~H"""
    <.warning_text id="published">
      Attendance cannot be changed once the activity is published. Unpublish it in D4H first.
    </.warning_text>
    """
  end

  defp send_section(assigns) do
    %{review: review, selected: selected} = assigns

    count =
      Enum.count(review.changes, &(SendAttendanceToD4H.sendable?(&1) and &1.key in selected))

    assigns = assign(assigns, :count, count)

    ~H"""
    <.form for={%{}} id="send-form" phx-change="select" phx-submit="send">
      <p :if={@review.changes == []} id="no-changes">
        No changes. D4H has no members signed up and nobody has arrived.
      </p>
      <.table
        :if={@review.changes != []}
        id="changes"
        rows={@review.changes}
        row_id={&"change-#{&1.key}"}
        class="table-striped table-stack"
      >
        <:col :let={change} label="" class="w-px stack-check">
          <input
            :if={SendAttendanceToD4H.sendable?(change)}
            type="checkbox"
            id={"select-#{change.key}"}
            name="keys[]"
            value={change.key}
            checked={change.key in @selected}
          />
        </:col>
        <:col :let={change} label="Member" class="stack-title">
          <label for={"select-#{change.key}"}>{change.member.name}</label>
        </:col>
        <:col :let={change} label="Change">
          <span class={action_class(change.action)}>{action_text(change.action)}</span>
        </:col>
        <:col :let={change} label="Times" class="whitespace-nowrap stack-optional">
          <span :if={change.arrived_at}>
            {Service.Format.time_short(change.arrived_at, @activity.team.timezone)}–{Service.Format.time_short(
              change.left_at,
              @activity.team.timezone
            )}
          </span>
        </:col>
        <:col :let={change} label="In D4H now">{status_text(change.status)}</:col>
        <:col :let={change} label="Notes" class="stack-full stack-optional">
          <span :for={note <- change.notes} class={["block", note_class(note)]}>
            {note_text(note)}
          </span>
        </:col>
      </.table>
      <.form_actions class="mt-2">
        <.button id="send" variant={:success} disabled={@count == 0} phx-disable-with="Sending…">
          Send {Service.Format.count(@count, one: "%d change", many: "%d changes")}
        </.button>
        <.button type="button" phx-click="cancel-review">Cancel</.button>
      </.form_actions>
    </.form>
    """
  end

  defp action_text(:update), do: "Attended"
  defp action_text(:create), do: "Attended, not signed up"
  defp action_text(:absent), do: "Absent"
  defp action_text(:unchanged), do: "No change"
  defp action_text(:blocked), do: "Fix the times first"

  defp action_class(:absent), do: "text-danger-text font-semibold"
  defp action_class(:blocked), do: "text-danger-text"
  defp action_class(:unchanged), do: "text-text-muted"
  defp action_class(_action), do: "text-success-text font-semibold"

  defp status_text(nil), do: "Not listed"
  defp status_text("requested"), do: "Signed up"
  defp status_text("attending"), do: "Attending"
  defp status_text("absent"), do: "Absent"
  defp status_text(status), do: status

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
        The link works until you close it or send to D4H. Anyone with it sees your members'
        names, and the mobile numbers of members who signed up and have not arrived.
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
        Send this link to the person taking attendance at the door. It works until you close
        it or send to D4H.
      </p>
      <div class="flex flex-wrap gap-2 items-center">
        <.a
          id="attendance-link-url"
          href={link_url(@link)}
          external={true}
          class="font-mono break-all"
        >
          {link_url(@link)}
        </.a>
        <.button
          id="copy-link"
          type="button"
          size={:sm}
          phx-click={
            JS.dispatch("sarduty:copy", to: "#attendance-link-url", detail: %{status: "#copy-status"})
          }
        >
          Copy link
        </.button>
        <.button
          id="share-link"
          type="button"
          size={:sm}
          phx-hook="ShareLink"
          data-url={link_url(@link)}
          hidden
        >
          Share link
        </.button>
        <span
          id="copy-status"
          role="status"
          phx-update="ignore"
          class="text-success-text font-semibold"
        ></span>
      </div>
      <div class="mt-2 flex flex-wrap gap-4 items-center">
        <.a
          id="create-link"
          href="#"
          phx-click="create-link"
          data-confirm="Make a new link? This link stops working."
        >
          Make new link
        </.a>
        <.button
          id="close-link"
          variant={:danger}
          size={:sm}
          phx-click="close-link"
          data-confirm="Close this link? It stops taking attendance."
        >
          Close link
        </.button>
      </div>
    </div>
    """
  end

  # Links made before short links have none, so they show the long one.
  defp link_url(%AttendanceLink{short_link: %ShortLink{} = short_link}),
    do: url(~p"/s/#{short_link.code}")

  defp link_url(%AttendanceLink{token: token}), do: url(~p"/attendance/#{token}")

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
      the start time for anyone who arrives within {BuildAttendanceTimes.grace_minutes()} minutes
      of the start, early or late. It uses the end time for anyone who leaves within {BuildAttendanceTimes.grace_minutes()} minutes of the end.
    </p>
    <.table id="times" rows={@times} class="table-striped table-stack md:w-fit">
      <:col :let={row} label="Name" class="stack-title">{row.member.name}</:col>
      <:col :let={row} label="Arrived" align="right">
        {Service.Format.time_short(row.arrived_at, @activity.team.timezone)}
      </:col>
      <:col :let={row} label="Left" align="right">
        {Service.Format.time_short(row.left_at, @activity.team.timezone)}
      </:col>
      <:col :let={row} label="Notes" class="stack-full stack-optional">
        <span :for={note <- row.notes} class={["block", note_class(note)]}>{note_text(note)}</span>
      </:col>
    </.table>
    """
  end

  defp note_class(:left_before_arriving), do: "text-danger-text"
  defp note_class(:attending_without_scan), do: "font-semibold"
  defp note_class(_note), do: "text-text-muted"

  defp note_text(:no_arrival), do: "No arrival scan. Uses the start time."
  defp note_text(:no_departure), do: "No departure scan. Uses the end time."
  defp note_text(:left_before_arriving), do: "Left before arriving. Fix the times at the door."

  defp note_text(:attending_without_scan),
    do: "Attending in D4H, but no scan. Check before sending."
end
