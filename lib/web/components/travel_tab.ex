defmodule Web.Components.TravelTab do
  @moduledoc """
  An activity's Travel tab (#230), for team admins from the start: how each attended
  row got there, and its km. Laid out like Remove members (#704): a table for rows not
  set and one for rows set, each with select all, and nothing checked. A button sets
  the checked rows, or Clear takes theirs away, one change at a time. Round trips come
  from the saved Mapbox lookups, so only a first visit waits for Mapbox. Once the
  activity is published, nothing changes, as with its attendance.

  Assigns: `team`, `activity`, `user`, and `service`. Members check theirs on the
  activity's page (Web.Components.TravelCheck); nothing waits on them. It sends
  `{:travel_flash, kind, text}` to the page for its toast.
  """
  use Web, :live_component

  import Web.Components.Columns, only: [member_cell: 1]
  import Web.Components.CopyButton, only: [copy_code_block: 1]
  import Web.Components.Table, only: [table: 1]

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Operation.SetTravel
  alias App.ViewData.ActivityTravel
  alias Service.Format

  def update(assigns, socket) do
    first? = !Map.has_key?(socket.assigns, :travel)

    socket =
      socket
      |> assign(assigns)
      |> assign(locked?: Activity.locked?(assigns.activity))
      |> assign_new(:selected, fn -> MapSet.new() end)
      |> assign_new(:km, fn -> "" end)

    {:ok, if(first?, do: load(socket), else: socket)}
  end

  defp load(socket) do
    %{team: team, activity: activity} = socket.assigns

    assign_async(socket, :travel, fn ->
      {:ok, %{travel: ActivityTravel.load(team, activity, DateTime.utc_now())}}
    end)
  end

  defp flash(socket, kind, text) do
    send(self(), {:travel_flash, kind, text})
    socket
  end

  def handle_event("change", params, socket) do
    {:noreply,
     assign(socket,
       selected: params |> selected_ids() |> MapSet.new(),
       km: Map.get(params, "km", socket.assigns.km)
     )}
  end

  def handle_event("set", params, socket) do
    %{team: team, user: user, activity: activity} = socket.assigns
    ids = selected_ids(params)
    now = DateTime.utc_now()

    case SetTravel.call(team, activity, user, ids, params["travel"], params["km"], now) do
      {:ok, result} ->
        kind = if result.skipped == [], do: :info, else: :error

        {:noreply,
         socket
         |> flash(kind, SetTravel.result_text(result))
         |> assign(selected: MapSet.new(), km: "")
         |> load()}

      {:error, reason} ->
        {:noreply, flash(socket, :error, SetTravel.error_text(team, reason))}
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
    <div id={@id}>
      <p id="travel-intro" class="measure">
        Round trips by car from each member's home, worked out once. A passenger counts 0 km.
      </p>
      <p :if={@locked?} id="travel-locked" class="hint measure">
        Published, so travel can't be changed. {D4H.unpublish_text(@team)}
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

        <.form
          :if={travel.rows != []}
          for={%{}}
          id="travel-form"
          phx-change="change"
          phx-submit="set"
          phx-target={@myself}
        >
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
                <.row_name row={row} team={@team} service={@service} locked?={@locked?} />
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
                <.row_name row={row} team={@team} service={@service} locked?={@locked?} />
              </:col>
              <:col :let={row} label="Travel" class="whitespace-nowrap">
                {ActivityTravel.travel_text(row.trip.travel)}
              </:col>
              <:col :let={row} align="right" label="km">{Format.km(row.trip.km)}</:col>
            </.table>
          </div>

          <%!-- The count sits on its own line, so the buttons keep their words and their
               places as rows are checked. --%>
          <p :if={!@locked?} id="travel-selection" class="mt-8 mb-2">
            {selection_text(MapSet.size(@selected))}
          </p>
          <.form_actions :if={!@locked?}>
            <.button
              :for={
                {travel_kind, text} <- [{"icp", "ICP"}, {"yard", "Yard"}, {"passenger", "Passenger"}]
              }
              id={"travel-set-#{travel_kind}"}
              name="travel"
              value={travel_kind}
              disabled={MapSet.size(@selected) == 0}
              phx-disable-with="Setting…"
            >
              {text}
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
                Set km
              </.button>
            </span>
            <:trailing>
              <.button
                id="travel-clear"
                name="travel"
                value="clear"
                disabled={clear_count(@selected, travel.set) == 0}
                phx-disable-with="Clearing…"
              >
                Clear
              </.button>
            </:trailing>
          </.form_actions>
        </.form>

        <section :if={travel.set != []} id="travel-check" class="mt-8 measure">
          <h2 class="heading">Members check</h2>
          <p id="travel-checked">
            Members can check theirs before you publish, on the activity's page and their Dashboard. {checked_text(
              travel.set
            )}
          </p>
          <p :if={!@team.member_logins} id="travel-no-logins" class="hint">
            Members can't log in to this team, so they can't check theirs.
          </p>
        </section>

        <details
          :if={travel.set != [] and !D4H.records?(@team)}
          id="travel-d4h"
          class="mt-8 measure"
        >
          <summary class="heading cursor-pointer">Copy into {@service}</summary>
          <p class="mt-3">
            {@service} has no way for SAR Duty to write mileage. Open activity {@activity.ref_id}'s mileage page in {@service}, paste this into a browser agent such as Claude in Chrome, then check its work and save. Then publish: travel can't be changed after that.
          </p>
          <.copy_code_block
            id="travel-d4h-prompt"
            value={ActivityTravel.d4h_prompt(travel, @team, @activity)}
            label={"Copy for #{@service}"}
          />
        </details>
      </.async_result>
    </div>
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
    <span :if={@row.trip && @row.trip.checked_at} class="hint block">Checked</span>
    """
  end

  defp home_text(:no_address, service), do: "No home address in #{service}. Type their km."
  defp home_text(:not_found, _service), do: "Mapbox couldn't find their address. Type their km."
  defp home_text(:unknown, _service), do: "Mapbox didn't answer. Reload the page to try again."

  # "3 of 7 members have checked." A member with two rows has checked when both are.
  defp checked_text(set) do
    by_member = Enum.group_by(set, & &1.member.id)
    checked = Enum.count(by_member, fn {_id, rows} -> Enum.all?(rows, & &1.trip.checked_at) end)

    "#{checked} of #{members_text(map_size(by_member))} #{if checked == 1, do: "has", else: "have"} checked."
  end

  defp members_text(count), do: Format.count(count, one: "%d member", many: "%d members")

  # Clear counts only the checked rows that are set.
  defp clear_count(selected, set),
    do: Enum.count(set, &MapSet.member?(selected, &1.attendance.id))

  defp selection_text(0), do: "Check rows, then set how they got there."

  defp selection_text(count),
    do: "#{Format.count(count, one: "%d row", many: "%d rows")} checked. Set them to:"
end
