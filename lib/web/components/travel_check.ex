defmodule Web.Components.TravelCheck do
  @moduledoc """
  Your travel on an activity's page (#230): the trip a team admin set for each of the
  member's attended rows, with That's right and Change until the activity is published.

  Assigns: `team`, `activity`, `member` (from `Reply.replier/2`), `user`, `viewing_as`
  (nil unless a team admin is viewing as the member), and `now`. Like ReplyControl, its
  events skip the team pages' hook (#440), so it refuses a team admin viewing as the
  member itself. It sends `{:travel_checked, text}` or `{:travel_failed, text}` to the
  page for its flash. It renders nothing when no trip is set.
  """
  use Web, :live_component

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Trip
  alias App.Operation.BuildMileageReport
  alias App.Operation.CheckTravel
  alias App.Repo
  alias App.ViewData.ActivityTravel
  alias Service.Format
  alias Web.UserAuth

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:changing, fn -> nil end)
     |> assign_new(:choices, fn -> [] end)
     |> load()}
  end

  # The member's attended rows that have a trip, with the trip and who set it.
  defp load(socket) do
    %{activity: activity, member: member, now: now} = socket.assigns
    trips = if member, do: Trip.for_member(activity, member), else: %{}

    rows = if trips == %{}, do: [], else: with_trips(activity, member, now, trips)

    assign(socket, rows: rows, locked?: Activity.locked?(activity))
  end

  defp with_trips(activity, member, now, trips) do
    Attendance
    |> Attendance.attended(now)
    |> where([r], r.activity_id == ^activity.id and r.member_id == ^member.id)
    |> order_by([r], asc: r.started_at)
    |> Repo.all()
    |> Enum.flat_map(fn row ->
      case trips[row.d4h_attendance_id] do
        nil -> []
        trip -> [%{attendance: row, trip: trip}]
      end
    end)
  end

  def handle_event(_event, _params, %{assigns: %{viewing_as: %Member{} = viewing_as}} = socket) do
    send(self(), {:travel_failed, UserAuth.view_as_refusal(viewing_as)})
    {:noreply, socket}
  end

  def handle_event("right", %{"id" => id}, socket), do: save(socket, id, "right", nil)

  def handle_event("change", %{"id" => id}, socket) do
    %{team: team, activity: activity, member: member} = socket.assigns
    report = BuildMileageReport.call(team, activity, DateTime.utc_now(), member: member)
    row = Enum.find(report.rows, &(to_string(&1.attendance.d4h_attendance_id) == id))
    {:noreply, assign(socket, changing: id, choices: choices(row))}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, changing: nil)}

  def handle_event("save", %{"row" => id} = params, socket),
    do: save(socket, id, params["travel"], params["km"])

  defp save(socket, id, choice, km_text) do
    %{team: team, activity: activity, member: member, user: user} = socket.assigns

    with {d4h_id, ""} <- Integer.parse(id),
         {:ok, _result} <-
           CheckTravel.call(
             team,
             activity,
             member,
             user,
             d4h_id,
             choice,
             km_text,
             DateTime.utc_now()
           ) do
      send(self(), {:travel_checked, "Saved your travel."})
      {:noreply, socket |> assign(changing: nil) |> load()}
    else
      {:error, reason} ->
        send(self(), {:travel_failed, CheckTravel.error_text(team, reason)})
        {:noreply, socket}

      _bad_id ->
        {:noreply, socket}
    end
  end

  # The four choices, each with its km: nil for a route Mapbox found none for.
  defp choices(nil), do: []

  defp choices(row) do
    [
      {"icp", "Drove to the ICP", row.activity_km},
      {"yard", "Drove to the yard", row.yard_km},
      {"passenger", "Passenger", 0}
    ]
  end

  def render(assigns) do
    ~H"""
    <section id={@id} class="mt-6 measure">
      <%= if @rows != [] do %>
        <h2 class="heading">Your travel</h2>
        <div :for={row <- @rows} id={"#{@id}-#{row.trip.d4h_attendance_id}"} class="mb-4">
          <%= if @changing == to_string(row.trip.d4h_attendance_id) do %>
            <.form
              for={%{}}
              id={"#{@id}-form"}
              class="reply-form"
              phx-submit="save"
              phx-target={@myself}
            >
              <input type="hidden" name="row" value={row.trip.d4h_attendance_id} />
              <fieldset>
                <legend>{day(row, @rows, @team)}How did you get there?</legend>
                <label :for={{travel, text, km} <- @choices} class="choice">
                  <input
                    type="radio"
                    name="travel"
                    value={travel}
                    checked={row.trip.travel == travel}
                    disabled={is_nil(km)}
                  />
                  {text}, {if km, do: Format.km(km), else: "no route"}
                </label>
                <label class="choice">
                  <input
                    type="radio"
                    name="travel"
                    value="other"
                    checked={row.trip.travel == "other"}
                  /> Other
                  <input
                    type="number"
                    name="km"
                    min="0"
                    step="1"
                    class="w-16"
                    value={if row.trip.travel == "other", do: row.trip.km}
                    aria-label="km"
                  /> km
                </label>
              </fieldset>
              <.form_actions>
                <.button id={"#{@id}-save"} variant={:primary} phx-disable-with="Saving…">
                  Save travel
                </.button>
                <.button type="button" id={"#{@id}-cancel"} phx-click="cancel" phx-target={@myself}>
                  Cancel
                </.button>
              </.form_actions>
            </.form>
          <% else %>
            <p class="mb-2">{day(row, @rows, @team)}{sentence(row, @team, @now)}</p>
            <p :if={@locked?} class="hint">Published, so travel can't be changed.</p>
            <div :if={!@locked?} class="flex flex-wrap gap-2">
              <.button
                :if={!row.trip.checked_at}
                id={"#{@id}-right-#{row.trip.d4h_attendance_id}"}
                variant={:success}
                phx-click="right"
                phx-disable-with="Saving…"
                phx-value-id={row.trip.d4h_attendance_id}
                phx-target={@myself}
              >
                That's right
              </.button>
              <.button
                id={"#{@id}-change-#{row.trip.d4h_attendance_id}"}
                phx-click="change"
                phx-disable-with="Working out km…"
                phx-value-id={row.trip.d4h_attendance_id}
                phx-target={@myself}
              >
                Change
              </.button>
            </div>
          <% end %>
        </div>
      <% end %>
    </section>
    """
  end

  # "Oct 30: " when the member has two rows.
  defp day(_row, [_one], _team), do: nil

  defp day(row, _rows, team),
    do: "#{Format.month_day(row.attendance.started_at, team.timezone)}: "

  defp sentence(%{trip: %{checked_at: nil} = trip}, team, now),
    do: "#{setter(trip, team, now)} set it: #{how(trip)}."

  defp sentence(%{trip: trip}, _team, _now),
    do:
      "#{String.capitalize(String.first(how(trip)))}#{String.slice(how(trip), 1..-1//1)}. Checked."

  defp setter(trip, team, now),
    do: Member.name_for_user(team, trip.set_by_user, now) || "A team admin"

  defp how(trip), do: ActivityTravel.trip_text(trip)
end
