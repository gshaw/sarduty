defmodule Web.Components.TravelTab do
  @moduledoc """
  An activity's Travel tab (#230), for team admins from the start: a table of the rows
  set, with how each got there and its km, then one of the rows not set, with each
  member's round trips to the ICP and the yard, which show the Mapbox routes are sane.
  Change on a row, or on the bar under the tables for every checked row, opens one
  dialog with the ways they got there: drove to the ICP or the yard at the saved round
  trip, a passenger at 0 km, Other with its km, or Not set. A row's dialog shows its km;
  the checked rows' dialog leaves it out, since each member's is their own. The bar sticks
  to the foot of the window, so its button stays in view on a long list. Under the rows
  set, their km in total. The tab's badge counts the rows not set.
  Round trips come from the saved Mapbox lookups, so only a first visit waits for Mapbox.
  Once the activity is published, nothing changes, as with its attendance.

  Assigns: `team`, `activity`, `user`, and `service`. Members confirm theirs on the
  activity's page (Web.Components.TravelCheck); nothing waits on them. It sends
  `{:travel_flash, kind, text}` to the page for its toast.
  """
  use Web, :live_component

  import Web.Components.Columns, only: [member_cell: 1]
  import Web.Components.CopyButton, only: [copy_code_block: 1]
  import Web.Components.Table, only: [table: 1]
  import Web.Components.TravelChoices, only: [travel_choices: 1]

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Operation.SetTravel
  alias App.ViewData.ActivityTravel
  alias Service.Format

  # The page asks again after Your travel saves the same rows.
  def update(%{reload: true}, socket), do: {:ok, load(socket)}

  def update(assigns, socket) do
    first? = !Map.has_key?(socket.assigns, :travel)

    socket =
      socket
      |> assign(assigns)
      |> assign(locked?: Activity.locked?(assigns.activity))
      |> assign_new(:selected, fn -> MapSet.new() end)
      |> assign_new(:editing, fn -> nil end)

    {:ok, if(first?, do: load(socket), else: socket)}
  end

  # The first load waits for Mapbox behind a spinner. Later loads keep the table showing,
  # since assign_async keeps the last result until the new one comes.
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

  # The checked rows, kept so a patch never unchecks them and the bar can count them.
  def handle_event("change", params, socket),
    do: {:noreply, assign(socket, selected: params |> selected_ids() |> MapSet.new())}

  # The bar's Change: one dialog for every checked row, which for one row is that row's own.
  def handle_event("edit_checked", _params, socket) do
    if MapSet.size(socket.assigns.selected) == 0,
      do: {:noreply, flash(socket, :error, "Check the members to change first.")},
      else: {:noreply, assign(socket, editing: :checked)}
  end

  # A row's Change: a dialog with every way for that row, Not set too.
  def handle_event("edit", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {id, ""} -> {:noreply, assign(socket, editing: {:row, id})}
      _other -> {:noreply, socket}
    end
  end

  # Cancel or Escape: nothing changes, and the rows stay checked.
  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, editing: nil)}

  # A row's own Change keeps the checked rows checked; the bar's are done once saved.
  def handle_event("save_travel", params, %{assigns: %{editing: {:row, id}}} = socket),
    do: set(socket, [id], params, socket.assigns.selected)

  def handle_event("save_travel", params, %{assigns: %{editing: :checked}} = socket),
    do: set(socket, MapSet.to_list(socket.assigns.selected), params, MapSet.new())

  def handle_event("save_travel", _params, socket), do: {:noreply, socket}

  defp set(socket, ids, params, selected) do
    %{team: team, user: user, activity: activity} = socket.assigns
    socket = assign(socket, editing: nil)
    travel = params["travel"]
    km = params["km"] || ""

    case SetTravel.call(team, activity, user, ids, travel, km, DateTime.utc_now()) do
      {:ok, plan} ->
        kind = if SetTravel.ok?(plan), do: :info, else: :error

        {:noreply,
         socket
         |> flash(kind, SetTravel.result_text(plan))
         |> assign(selected: selected)
         |> load()}

      {:error, reason} ->
        {:noreply, flash(socket, :error, SetTravel.error_text(team, reason))}
    end
  end

  # The checked rows' members, for the bar's button: a member with two rows counts once.
  defp checked_members(travel, selected),
    do:
      travel.rows
      |> Enum.filter(&MapSet.member?(selected, &1.attendance.id))
      |> Enum.uniq_by(& &1.member.id)
      |> length()

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
      <.async_result :let={travel} assign={@travel}>
        <:loading>
          <.spinner>Working out driving distances…</.spinner>
        </:loading>
        <:failed>
          <p id="travel-error">Travel did not load. Reload the page to try again.</p>
        </:failed>

        <p :if={@locked?} id="travel-locked" class="hint measure">
          Published, so travel cannot be changed. {D4H.unpublish_text(@team)}
        </p>
        <p :if={!@activity.coordinate} id="travel-no-location" class="hint measure">
          The activity has no latitude and longitude, so there's no route to the ICP. Check their rows and choose Other.
        </p>

        <p :if={travel.rows == []} id="travel-nobody">Nobody attended.</p>

        <.form
          :if={travel.rows != []}
          for={%{}}
          id="travel-form"
          phx-change="change"
          phx-submit="edit_checked"
          phx-target={@myself}
        >
          <div :if={travel.set != []} class="mb-6">
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
                <.member_cell
                  member={row.member}
                  team={@team}
                  label_for={if !@locked?, do: "travel-select-#{row.attendance.id}"}
                />
                <.row_hints row={row} team={@team} service={@service} />
              </:col>
              <:col :let={row} label="Travel" class="whitespace-nowrap">
                {ActivityTravel.travel_text(row.trip.travel)}
              </:col>
              <:col :let={row} label="km" align="right" class="whitespace-nowrap">
                {Format.km(row.trip.km)}
              </:col>
              <:col :let={row} :if={!@locked?} label="" class="w-px">
                <.change_button row={row} myself={@myself} />
              </:col>
            </.table>
            <p id="travel-total" class="hint mt-2">
              {Format.km(Enum.sum_by(travel.set, & &1.trip.km))} in total
            </p>
          </div>

          <%!-- Not set sits last, next to the bar that sets it. --%>
          <.table
            :if={travel.not_set != []}
            id="travel-not-set"
            rows={travel.not_set}
            row_id={&"travel-row-#{&1.attendance.id}"}
            class="table-striped"
          >
            <:col :let={row} :if={!@locked?} label="" class="w-px" select_all>
              <.row_box row={row} selected={@selected} />
            </:col>
            <:col :let={row} label="Not set">
              <.member_cell
                member={row.member}
                team={@team}
                label_for={if !@locked?, do: "travel-select-#{row.attendance.id}"}
              />
              <.row_hints row={row} team={@team} service={@service} />
            </:col>
            <:col :let={row} label="To the ICP" align="right" class="whitespace-nowrap">
              <.route km={row.activity_km} />
            </:col>
            <:col :let={row} label="To the yard" align="right" class="whitespace-nowrap">
              <.route km={row.yard_km} />
            </:col>
            <:col :let={row} :if={!@locked?} label="" class="w-px">
              <.change_button row={row} myself={@myself} />
            </:col>
          </.table>

          <%!-- Sticks to the foot of the window, so its button stays in view on a long list. --%>
          <div :if={!@locked?} id="travel-bar" class="travel-bar">
            <.button
              type="button"
              id="travel-change-checked"
              variant={:primary}
              phx-click="edit_checked"
              phx-target={@myself}
            >
              {change_text(checked_members(travel, @selected))}
            </.button>
            <span :if={MapSet.size(@selected) == 0} id="travel-bar-hint" class="hint">
              Check members, then change their travel together.
            </span>
          </div>
        </.form>

        <.travel_dialog
          :if={@editing}
          rows={dialog_rows(travel, @editing, @selected)}
          myself={@myself}
        />

        <section :if={travel.set != []} id="travel-check" class="mt-8 measure">
          <h2 class="heading">Members confirm</h2>
          <p id="travel-checked">
            Members can confirm theirs before you publish, on the activity's page and their Dashboard. {members_checked_text(
              travel.set
            )}
          </p>
          <p :if={!@team.member_logins} id="travel-no-logins" class="hint">
            Members can't log in to this team, so they can't confirm theirs.
          </p>
        </section>

        <details
          :if={travel.set != [] and !D4H.records?(@team)}
          id="travel-d4h"
          class="mt-8 measure"
        >
          <summary class="heading cursor-pointer">Copy into {@service}</summary>
          <p class="mt-3">
            {@service} has no way for SAR Duty to write mileage. Open activity {@activity.ref_id}'s mileage page in {@service}, paste this into a browser agent such as Claude in Chrome, then check its work and save. Then publish: travel cannot be changed after that.
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
  attr :myself, :any, required: true

  # A row's Change, which opens its dialog with every way, Not set too.
  defp change_button(assigns) do
    ~H"""
    <.button
      type="button"
      size={:sm}
      id={"travel-change-#{@row.attendance.id}"}
      phx-click="edit"
      phx-value-id={@row.attendance.id}
      phx-target={@myself}
      aria-label={"Change #{@row.member.name}'s travel"}
    >
      Change
    </.button>
    """
  end

  defp change_text(0), do: "Change members"

  defp change_text(count),
    do: Format.count(count, one: "Change 1 member", many: "Change %d members")

  # The rows a dialog changes: the one row, or every checked row. None when they've gone,
  # such as after a sync, and then no dialog.
  defp dialog_rows(travel, {:row, id}, _selected),
    do: Enum.filter(travel.rows, &(&1.attendance.id == id))

  defp dialog_rows(travel, :checked, selected),
    do: Enum.filter(travel.rows, &MapSet.member?(selected, &1.attendance.id))

  attr :km, :integer, default: nil

  # A round trip from home, or No route when Mapbox found none.
  defp route(assigns) do
    ~H"""
    <span :if={@km}>{Format.km(@km)}</span>
    <span :if={!@km} class="hint">No route</span>
    """
  end

  attr :rows, :list, required: true, doc: "one row, or the checked rows"
  attr :myself, :any, required: true

  # Travel in the confirm dialog, every way at once, starting on what's saved for one row.
  # For several, the ways without km, since each member's round trip is their own.
  # Its id names what it changes, so the next Change opens a new dialog.
  defp travel_dialog(%{rows: []} = assigns), do: ~H""

  defp travel_dialog(assigns) do
    {one, current} =
      case assigns.rows do
        [row] -> {row, if(row.trip, do: row.trip.travel, else: "clear")}
        _rows -> {nil, nil}
      end

    assigns =
      assign(assigns,
        one: one,
        current: current,
        id: if(one, do: to_string(one.attendance.id), else: "checked"),
        question:
          if(one,
            do: "#{one.member.name}'s travel",
            else: assigns.rows |> Enum.uniq_by(& &1.member.id) |> length() |> members_travel()
          )
      )

    ~H"""
    <.confirm_dialog
      id={"travel-edit-dialog-#{@id}"}
      phx-hook="AskDialog"
      phx-target={@myself}
      phx-mounted={JS.ignore_attributes(["open"])}
      data-confirm-event="save_travel"
      data-cancel-event="cancel_edit"
      question={@question}
      action="Save travel"
    >
      <.travel_choices
        id={"travel-#{@id}"}
        class="confirm-dialog-choices mb-0"
        legend="How they got there"
        hint={if @one, do: "Round trips from home.", else: "Each member's own round trip from home."}
        routes={@one}
        current={@current}
        km={@one && @one.trip && @one.trip.km}
        clear?={true}
      />
    </.confirm_dialog>
    """
  end

  defp members_travel(count),
    do: Format.count(count, one: "1 member's travel", many: "%d members' travel")

  attr :row, :map, required: true
  attr :team, :any, required: true
  attr :service, :string, required: true

  # Under the member: the day when they came on two, why a row has no route, and Confirmed.
  defp row_hints(assigns) do
    ~H"""
    <span :if={@row.two_rows?} class="hint block">
      {Format.month_day(@row.attendance.started_at, @team.timezone)}
    </span>
    <span :if={is_atom(@row.home) and !@row.trip} class="hint block">
      {home_text(@row.home, @service)}
    </span>
    <span :if={@row.trip && @row.trip.checked_at} class="hint block">Confirmed</span>
    """
  end

  defp home_text(:no_address, service), do: "No home address in #{service}, so choose Other."

  defp home_text(:not_found, _service),
    do: "Mapbox could not find their address, so choose Other."

  defp home_text(:unknown, _service), do: "Mapbox didn't answer. Reload the page to try again."

  # "3 of 7 members have confirmed." A member with two rows has when both are.
  defp members_checked_text(set) do
    by_member = Enum.group_by(set, & &1.member.id)
    checked = Enum.count(by_member, fn {_id, rows} -> Enum.all?(rows, & &1.trip.checked_at) end)

    "#{checked} of #{members_text(map_size(by_member))} #{if checked == 1, do: "has", else: "have"} confirmed."
  end

  defp members_text(count), do: Format.count(count, one: "%d member", many: "%d members")
end
