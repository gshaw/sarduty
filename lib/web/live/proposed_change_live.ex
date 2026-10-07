defmodule Web.ProposedChangeLive do
  use Web, :live_view_app_layout

  alias App.Model.ChangeSet
  alias App.Operation.ApplyProposedChangeSet

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, params["id"])}
  end

  defp load(socket, id) do
    change_set = ChangeSet.find!(socket.assigns.current_team, id)
    waiting = for row <- change_set.rows, row.status == :proposed, do: row.id

    assign(socket,
      page_title: "Proposed changes",
      change_set: change_set,
      selected: MapSet.new(waiting)
    )
  end

  def handle_event("select", params, socket) do
    {:noreply, assign(socket, :selected, params |> selected_ids() |> MapSet.new())}
  end

  def handle_event("send", params, socket) do
    %{current_team: team, current_user: user, change_set: change_set} = socket.assigns
    now = DateTime.utc_now()

    case ApplyProposedChangeSet.call(team, change_set, user, selected_ids(params), now) do
      {:ok, rows} ->
        applied = Enum.count(rows, &(&1.status == :applied))
        not_sent = length(rows) - applied
        kind = if not_sent == 0, do: :info, else: :error

        message =
          "Sent #{count_changes(applied)} to D4H." <>
            if(not_sent > 0, do: " #{count_changes(not_sent)} did not go through.", else: "")

        {:noreply, socket |> put_flash(kind, message) |> load(change_set.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("discard", _params, socket) do
    change_set = socket.assigns.change_set

    if ChangeSet.waiting?(change_set), do: ChangeSet.discard!(change_set, DateTime.utc_now())

    {:noreply,
     socket
     |> put_flash(:info, "Discarded the proposed changes. Nothing changed in D4H.")
     |> push_navigate(to: ~p"/teams/#{socket.assigns.current_team}/proposed-changes")}
  end

  defp selected_ids(params) do
    params
    |> Map.get("row_ids", [])
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {id, ""} -> [id]
        _ -> []
      end
    end)
  end

  defp count_changes(n), do: Service.Format.count(n, one: "%d change", many: "%d changes")

  defp error_text(:decided), do: "These changes were already sent or discarded."
  defp error_text(:none_selected), do: "Select at least 1 change to send."
  defp error_text(:no_team_key), do: "Save the team's D4H access key in Team settings first."

  defp error_text(:published),
    do: "Attendance cannot be changed. The activity is published in D4H."

  defp error_text(:deleted), do: "Attendance cannot be changed. The activity is deleted in D4H."
  defp error_text(error), do: "D4H did not answer. Try again. #{Exception.message(error)}"

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Proposed changes" path={~p"/teams/#{@current_team}/proposed-changes"} />
      <:item label={"#{@change_set.id}"} />
    </.breadcrumbs>

    <h1 class="title">{@change_set.summary || "Attendance changes"}</h1>
    <dl id="change-set-details" class="mb-p">
      <div :if={@change_set.activity}>
        <dt>Activity</dt>
        <dd>
          <.a navigate={~p"/teams/#{@current_team}/activities/#{@change_set.activity.id}"}>
            {@change_set.activity.title}
          </.a>
        </dd>
      </div>
      <div>
        <dt>Proposed</dt>
        <dd>
          {Service.Format.month_day_time(@change_set.inserted_at, @current_team.timezone)}, by an AI
          agent for {(@change_set.proposed_by_user && @change_set.proposed_by_user.email) ||
            "a deleted account"}
        </dd>
      </div>
      <div :if={@change_set.applied_at}>
        <dt>Sent to D4H</dt>
        <dd>
          {Service.Format.month_day_time(@change_set.applied_at, @current_team.timezone)}, by {@change_set.applied_by_user &&
            @change_set.applied_by_user.email}
        </dd>
      </div>
      <div :if={@change_set.discarded_at}>
        <dt>Discarded</dt>
        <dd>{Service.Format.month_day_time(@change_set.discarded_at, @current_team.timezone)}</dd>
      </div>
    </dl>

    <p :if={ChangeSet.waiting?(@change_set)} class="text-secondary-1 mb-p">
      Clear the box next to any change you do not want. SAR Duty reads D4H again before it
      sends, and skips a change if someone changed that attendance in D4H first.
    </p>

    <.form for={%{}} id="review-form" phx-change="select" phx-submit="send">
      <.table
        id="proposed-rows"
        rows={@change_set.rows}
        row_id={&"row-#{&1.id}"}
        class="w-full table-striped table-stack mb-p"
      >
        <:col :let={row} :if={ChangeSet.waiting?(@change_set)} label="" class="w-px">
          <input
            type="checkbox"
            id={"select-#{row.id}"}
            name="row_ids[]"
            value={row.id}
            checked={MapSet.member?(@selected, row.id)}
            disabled={row.status != :proposed}
          />
        </:col>
        <:col :let={row} label="Member">
          <label for={"select-#{row.id}"}>{row.member && row.member.name}</label>
        </:col>
        <:col :let={row} label="Change">
          {describe(row, @current_team.timezone)}
          <div :if={row.reason} class="text-secondary-1">{row.reason}</div>
        </:col>
        <:col :let={row} :if={!ChangeSet.waiting?(@change_set)} label="Result">
          {result(row)}
        </:col>
      </.table>

      <div :if={ChangeSet.waiting?(@change_set)} class="flex flex-wrap gap-2">
        <.button
          id="send"
          variant={:primary}
          disabled={MapSet.size(@selected) == 0 || is_nil(@current_team.d4h_access_key)}
          phx-disable-with="Sending…"
        >
          Send {count_changes(MapSet.size(@selected))}
        </.button>
        <.button
          id="discard"
          type="button"
          phx-click="discard"
          data-confirm="Discard these proposed changes? Nothing changes in D4H."
        >
          Discard changes
        </.button>
      </div>
    </.form>
    """
  end

  defp describe(row, tz) do
    status = status(row.new_value["status"])
    times = times(row.new_value["starts_at"], row.new_value["ends_at"], tz)

    case row.action do
      :create_attendance -> "Add as #{status}#{times}"
      :update_attendance -> "#{status(row.old_value["status"])} to #{status}#{times}"
    end
  end

  defp status(nil), do: "not listed"

  defp status(status) do
    case String.downcase(status) do
      "attending" -> "attended"
      other -> other
    end
  end

  defp times(nil, nil, _tz), do: ""

  defp times(starts_at, ends_at, tz),
    do: ", #{time(starts_at, tz)} to #{time(ends_at, tz)}"

  defp time(nil, _tz), do: "not set"

  defp time(iso, tz) do
    {:ok, datetime, _} = DateTime.from_iso8601(iso)
    Service.Format.month_day_time(datetime, tz)
  end

  defp result(%{status: :applied}), do: "Sent"
  defp result(%{status: :skipped, error: error}), do: "Skipped. #{error}"
  defp result(%{status: :failed, error: error}), do: "Did not go through. #{error}"
  defp result(%{status: :proposed}), do: "Not sent"
end
