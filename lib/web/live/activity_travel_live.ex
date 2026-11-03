defmodule Web.ActivityTravelLive do
  use Web, :live_view_app_layout

  import Web.Components.CopyButton, only: [copy_code_block: 1]

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Operation.SetTravel
  alias App.ViewData.ActivityTravel
  alias Service.Format

  # How each attended row got to the activity, and its km (#230), in place of the old
  # Mileage report. Laid out like Remove members (#704): a table for rows not set and
  # one for rows set, each with select all, and nothing checked. A button sets the
  # checked rows, one change at a time, and the page stays open for the next. Round
  # trips come from the saved Mapbox lookups, so only a first visit waits for Mapbox.
  # Once the activity is published, nothing changes, as with its attendance.
  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(%{"id" => id}, _uri, socket) do
    team = socket.assigns.current_team
    activity = Web.ActivityLive.fetch_activity(team, id)

    if Activity.deleted?(activity) do
      {:noreply, Web.ActivityLive.leave_deleted(socket, activity)}
    else
      {:noreply,
       socket
       |> assign(
         page_title: "#{activity.title} · Travel",
         activity: activity,
         locked?: Activity.locked?(activity),
         selected: MapSet.new(),
         km: ""
       )
       |> load()}
    end
  end

  defp load(socket) do
    %{current_team: team, activity: activity} = socket.assigns

    assign_async(socket, :travel, fn ->
      {:ok, %{travel: ActivityTravel.load(team, activity, DateTime.utc_now())}}
    end)
  end

  def handle_event("change", params, socket) do
    {:noreply,
     assign(socket,
       selected: params |> selected_ids() |> MapSet.new(),
       km: Map.get(params, "km", socket.assigns.km)
     )}
  end

  def handle_event("set", params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns
    ids = selected_ids(params)

    case SetTravel.call(
           team,
           activity,
           user,
           ids,
           params["travel"],
           params["km"],
           DateTime.utc_now()
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(
           if(result.skipped == [], do: :info, else: :error),
           SetTravel.result_text(result)
         )
         |> assign(selected: MapSet.new(), km: "")
         |> load()}

      {:error, :deleted} ->
        {:noreply, Web.ActivityLive.leave_deleted(socket, activity)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, SetTravel.error_text(team, reason))}
    end
  end

  # Ids come from the browser; SetTravel sets only rows the page shows.
  defp selected_ids(params) do
    params
    |> Map.get("row_ids", [])
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {id, ""} -> [id]
        _other -> []
      end
    end)
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item label={@activity.ref_id} path={~p"/teams/#{@current_team}/activities/#{@activity.id}"} />
      <:item label="Travel" />
    </.breadcrumbs>
    <h1 class="title">Travel</h1>
    <p class="lead">
      {@activity.title} · {Format.datetime_medium(@activity.started_at, @current_team.timezone)}
    </p>
    <p id="travel-intro" class="measure">
      Round trips by car from each member's home, worked out once. The ICP is the activity's location, and the yard is the team's. Check rows, then set how they got there. A passenger counts 0 km.
    </p>
    <p :if={@locked?} id="travel-locked" class="hint measure">
      Published, so travel can't be changed. {D4H.unpublish_text(@current_team)}
    </p>
    <p :if={!@activity.coordinate} id="travel-no-location" class="hint measure">
      The activity has no latitude and longitude, so there's no route to the ICP. Type their km instead.
    </p>

    <.async_result :let={travel} assign={@travel}>
      <:loading>
        <.spinner>Working out driving distances…</.spinner>
      </:loading>
      <:failed>
        <p id="travel-error">Travel did not load. Reload the page to try again.</p>
      </:failed>

      <p :if={travel.rows == []} id="travel-nobody">Nobody attended.</p>

      <.form :if={travel.rows != []} for={%{}} id="travel-form" phx-change="change" phx-submit="set">
        <div :if={travel.not_set != []} class="measure mb-6">
          <.table
            id="travel-not-set"
            rows={travel.not_set}
            row_id={&"travel-row-#{&1.attendance.id}"}
            class="table-striped"
          >
            <:col :let={row} :if={!@locked?} label="" class="w-px" select_all>
              <.row_box row={row} selected={@selected} />
            </:col>
            <:col :let={row} label="Not set">
              <.row_name row={row} team={@current_team} service={@service} locked?={@locked?} />
            </:col>
            <:col :let={row} align="right" label="To the ICP">
              {row.activity_km && Format.km(row.activity_km)}
            </:col>
            <:col :let={row} align="right" label="To the yard">
              {row.yard_km && Format.km(row.yard_km)}
            </:col>
          </.table>
        </div>

        <div :if={travel.set != []} class="measure mb-6">
          <.table
            id="travel-set"
            rows={travel.set}
            row_id={&"travel-row-#{&1.attendance.id}"}
            class="table-striped"
          >
            <:col :let={row} :if={!@locked?} label="" class="w-px" select_all>
              <.row_box row={row} selected={@selected} />
            </:col>
            <:col :let={row} label="Set">
              <.row_name row={row} team={@current_team} service={@service} locked?={@locked?} />
            </:col>
            <:col :let={row} label="Travel" class="whitespace-nowrap">
              {ActivityTravel.travel_text(row.trip.travel)}
            </:col>
            <:col :let={row} align="right" label="km">{Format.km(row.trip.km)}</:col>
          </.table>
        </div>

        <.form_actions :if={!@locked?} class="mt-8">
          <.button
            :for={{travel_kind, to} <- [{"icp", "ICP"}, {"yard", "yard"}, {"passenger", "passenger"}]}
            id={"travel-set-#{travel_kind}"}
            name="travel"
            value={travel_kind}
            disabled={MapSet.size(@selected) == 0}
            phx-disable-with="Setting…"
          >
            {set_text(MapSet.size(@selected), to)}
          </.button>
          <span class="flex items-center gap-2">
            <input
              type="number"
              id="travel-km"
              name="km"
              value={@km}
              min="0"
              step="1"
              class="w-16"
              aria-label="km"
            />
            <.button
              id="travel-set-other"
              name="travel"
              value="other"
              disabled={MapSet.size(@selected) == 0 or @km == ""}
              phx-disable-with="Setting…"
            >
              {km_text(MapSet.size(@selected), @km)}
            </.button>
          </span>
        </.form_actions>
      </.form>

      <details
        :if={travel.set != [] and !D4H.records?(@current_team)}
        id="travel-d4h"
        class="mt-8 measure"
      >
        <summary class="heading cursor-pointer">Copy into {@service}</summary>
        <p class="mt-3">
          {@service} has no way for SAR Duty to write mileage. Open activity {@activity.ref_id}'s mileage page in {@service}, paste this into a browser agent such as Claude in Chrome, then check its work and save. Then publish: travel can't be changed after that.
        </p>
        <.copy_code_block
          id="travel-d4h-prompt"
          value={ActivityTravel.d4h_prompt(travel, @current_team, @activity)}
          label={"Copy for #{@service}"}
        />
      </details>
    </.async_result>
    """
  end

  attr :row, :map, required: true
  attr :selected, :any, required: true

  defp row_box(assigns) do
    ~H"""
    <input
      type="checkbox"
      id={"travel-select-#{@row.attendance.id}"}
      name="row_ids[]"
      value={@row.attendance.id}
      checked={MapSet.member?(@selected, @row.attendance.id)}
    />
    """
  end

  attr :row, :map, required: true
  attr :team, :any, required: true
  attr :service, :string, required: true
  attr :locked?, :boolean, required: true

  # The member, the day when they came on two, and why a row has no route.
  defp row_name(assigns) do
    ~H"""
    <.member_cell
      member={@row.member}
      team={@team}
      label_for={if !@locked?, do: "travel-select-#{@row.attendance.id}"}
    />
    <span :if={@row.two_rows?} class="hint block">
      {Format.month_day(@row.attendance.started_at, @team.timezone)}
    </span>
    <span :if={is_atom(@row.home) and !@row.trip} class="hint block">
      {home_text(@row.home, @service)}
    </span>
    """
  end

  defp home_text(:no_address, service), do: "No home address in #{service}. Type their km."
  defp home_text(:not_found, _service), do: "Mapbox couldn't find their address. Type their km."
  defp home_text(:unknown, _service), do: "Mapbox didn't answer. Reload the page to try again."

  defp set_text(0, to), do: "Set to #{to}"
  defp set_text(count, to), do: "Set #{count} to #{to}"

  defp km_text(0, _km), do: "Set km"
  defp km_text(count, ""), do: "Set #{count} to km"

  defp km_text(count, km) do
    case SetTravel.parse_km(km) do
      {:ok, km} -> "Set #{count} to #{Format.km(km)}"
      :error -> "Set #{count} to km"
    end
  end
end
