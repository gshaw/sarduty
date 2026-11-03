defmodule Web.Components.TravelCheck do
  @moduledoc """
  Your travel on an activity's page (#230): the trip a team admin set for each of the
  member's attended rows, with That's right and Change until the activity is published.
  A row with nothing set has Set travel, until then; once published it's left out.

  Assigns: `team`, `activity`, `member` (from `Reply.replier/2`), `user`, `viewing_as`
  (nil unless a team admin is viewing as the member), and `now`. Like ReplyControl, its
  events skip the team pages' hook (#440), so it refuses a team admin viewing as the
  member itself. It sends `{:travel_checked, text}` or `{:travel_failed, text}` to the
  page for its flash. It renders nothing when there's no row to show.
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

  # The member's attended rows, each with its trip and who set it, or nil when nothing
  # is set. Once published, a row with nothing set can't be, so it's left out.
  defp load(socket) do
    %{activity: activity, member: member, now: now} = socket.assigns
    locked? = Activity.locked?(activity)
    rows = if member, do: rows(activity, member, now, locked?), else: []
    assign(socket, rows: rows, locked?: locked?)
  end

  defp rows(activity, member, now, locked?) do
    trips = Trip.for_member(activity, member)

    Attendance
    |> Attendance.attended(now)
    |> where([r], r.activity_id == ^activity.id and r.member_id == ^member.id)
    |> order_by([r], asc: r.started_at)
    |> Repo.all()
    |> Enum.map(&%{id: &1.d4h_attendance_id, attendance: &1, trip: trips[&1.d4h_attendance_id]})
    |> Enum.reject(&(locked? and is_nil(&1.trip)))
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
    <section id={@id}>
      <%= if @rows != [] do %>
        <strong class="block mb-1">Your travel</strong>
        <div :for={row <- @rows} id={"#{@id}-#{row.id}"} class="mb-4">
          <%= if @changing == to_string(row.id) do %>
            <.form
              for={%{}}
              id={"#{@id}-form"}
              class="reply-form"
              phx-submit="save"
              phx-target={@myself}
            >
              <input type="hidden" name="row" value={row.id} />
              <fieldset>
                <legend>{day(row, @rows, @team)}How did you get there?</legend>
                <label :for={{travel, text, km} <- @choices} class="choice">
                  <input
                    type="radio"
                    name="travel"
                    value={travel}
                    checked={travel(row) == travel}
                    disabled={is_nil(km)}
                  />
                  {text}, {if km, do: Format.km(km), else: "no route"}
                </label>
                <label class="choice">
                  <input
                    type="radio"
                    name="travel"
                    value="other"
                    checked={travel(row) == "other"}
                  /> Other
                  <input
                    type="number"
                    name="km"
                    min="0"
                    step="1"
                    class="w-16"
                    value={if travel(row) == "other", do: row.trip.km}
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
                :if={row.trip && !row.trip.checked_at}
                id={"#{@id}-right-#{row.id}"}
                variant={:success}
                phx-click="right"
                phx-disable-with="Saving…"
                phx-value-id={row.id}
                phx-target={@myself}
              >
                That's right
              </.button>
              <.button
                id={"#{@id}-change-#{row.id}"}
                variant={if row.trip, do: :default, else: :primary}
                phx-click="change"
                phx-disable-with="Working out km…"
                phx-value-id={row.id}
                phx-target={@myself}
              >
                {if row.trip, do: "Change", else: "Set travel"}
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

  defp travel(%{trip: nil}), do: nil
  defp travel(%{trip: trip}), do: trip.travel

  defp sentence(%{trip: nil}, _team, _now), do: "Not set yet. How did you get there?"

  defp sentence(%{trip: %{checked_at: nil} = trip}, team, now),
    do: "#{setter(trip, team, now)} set it: #{how(trip)}."

  defp sentence(%{trip: trip}, _team, _now),
    do:
      "#{String.capitalize(String.first(how(trip)))}#{String.slice(how(trip), 1..-1//1)}. Checked."

  defp setter(trip, team, now),
    do: Member.name_for_user(team, trip.set_by_user, now) || "A team admin"

  defp how(trip), do: ActivityTravel.trip_text(trip)
end
