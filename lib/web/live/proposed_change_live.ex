defmodule Web.ProposedChangeLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Attendance
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
    # A chore that matches one logged already starts cleared, with why (#595).
    waiting = for row <- change_set.rows, row.status == :proposed, !check(row), do: row.id

    assign(socket,
      page_title: ChangeSet.proposal_title(change_set),
      change_set: change_set,
      kind: ChangeSet.proposal_kind(change_set),
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
        {kind, message} = sent_flash(rows)
        {:noreply, socket |> put_flash(kind, message) |> load(change_set.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason, team))}
    end
  end

  def handle_event("discard", _params, socket) do
    change_set = socket.assigns.change_set

    if ChangeSet.waiting?(change_set), do: ChangeSet.discard!(change_set, DateTime.utc_now())

    {:noreply,
     socket
     |> put_flash(:info, "Discarded the proposed changes. Nothing was sent.")
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

  defp sent_flash(rows) do
    applied = Enum.count(rows, &(&1.status == :applied))
    not_sent = length(rows) - applied
    kind = if not_sent == 0, do: :info, else: :error

    done =
      if Enum.any?(rows, &(&1.action == :add_chore)),
        do: "Added #{count_chores(applied)} to accept on the Chores page.",
        else: "Sent #{count_changes(applied)}."

    count =
      if Enum.any?(rows, &(&1.action == :add_chore)), do: &count_chores/1, else: &count_changes/1

    message = done <> if(not_sent > 0, do: " #{count.(not_sent)} did not go through.", else: "")

    {kind, message}
  end

  defp count_changes(n), do: Service.Format.count(n, one: "%d change", many: "%d changes")

  defp error_text(:decided, _team), do: "These changes were already sent or discarded."
  defp error_text(:none_selected, _team), do: "Select at least 1 change to send."
  defp error_text(:no_team_key, _team), do: "Save your team's access key in team settings first."

  defp error_text(:published, team),
    do: "Attendance cannot be changed once the activity is published. #{D4H.unpublish_text(team)}"

  defp error_text(:deleted, _team), do: "Attendance cannot be changed. The activity is deleted."
  defp error_text(error, team), do: D4H.error_text(team, error)

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Proposed changes" path={~p"/teams/#{@current_team}/proposed-changes"} />
      <:item label={"#{@change_set.id}"} />
    </.breadcrumbs>

    <h1 class="title">{@page_title}</h1>
    <dl id="change-set-details" class="mb-4">
      <div :if={@change_set.summary}>
        <dt>Agent's note</dt>
        <dd>{@change_set.summary}</dd>
      </div>
      <div :if={@change_set.activity}>
        <dt>Activity</dt>
        <dd>
          <.a navigate={~p"/teams/#{@current_team}/activities/#{@change_set.activity.id}"}>{@change_set.activity.title}</.a>
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
        <dt>Sent</dt>
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

    <p :if={ChangeSet.waiting?(@change_set) and @kind == :chores} id="what-happens" class="lead">
      Adds these chores to the Chores page, as if each member had logged their own. A team
      admin accepts them there before they count. Clear the box next to any chore you do not
      want.
    </p>
    <p :if={ChangeSet.waiting?(@change_set) and @kind == :attendance} id="what-happens" class="lead">
      Sending changes the activity's attendance. Clear the box next to any change you do not
      want. SAR Duty checks the attendance again before it sends, and skips a change if
      someone changed that attendance first.
    </p>
    <p
      :if={ChangeSet.waiting?(@change_set) and @kind == :activity_tags}
      id="what-happens"
      class="lead"
    >
      Sending changes the tags on these activities. Clear the box next to any change you do
      not want. SAR Duty checks each activity's tags again before it sends, and skips one
      that someone changed or published first.
    </p>

    <.form for={%{}} id="review-form" phx-change="select" phx-submit="send">
      <.table
        id="proposed-rows"
        rows={@change_set.rows}
        row_id={&"row-#{&1.id}"}
        class="table-striped table-stack"
      >
        <:col
          :let={row}
          :if={ChangeSet.waiting?(@change_set)}
          label=""
          class="w-px stack-check"
          select_all
        >
          <input
            type="checkbox"
            id={"select-#{row.id}"}
            name="row_ids[]"
            value={row.id}
            checked={MapSet.member?(@selected, row.id)}
            disabled={row.status != :proposed}
          />
        </:col>
        <:col
          :let={row}
          label={if @kind == :activity_tags, do: "Activity", else: "Member"}
          class="stack-title"
        >
          <label for={"select-#{row.id}"}>{subject(row)}</label>
        </:col>
        <:col :let={row} :if={@kind == :chores} label="Date" class="whitespace-nowrap">
          {row.new_value["date"] |> Date.from_iso8601!() |> Service.Format.date_short()}
        </:col>
        <:col :let={row} :if={@kind == :chores} label="Chore category">
          {row.new_value["category"]}
        </:col>
        <:col :let={row} :if={@kind == :chores} label="Time" class="whitespace-nowrap" align="right">
          {Service.Format.duration(row.new_value["minutes"])}
        </:col>
        <:col
          :let={row}
          label={if @kind == :chores, do: "What they did", else: "Change"}
          class="stack-full"
        >
          {if @kind == :chores,
            do: row.new_value["description"],
            else: describe(row, @change_set, @current_team.timezone)}
          <div :if={row.reason} class="hint">{row.reason}</div>
          <.warning_text :if={check(row) && ChangeSet.waiting?(@change_set)}>
            {check(row)}
          </.warning_text>
        </:col>
        <:col :let={row} :if={!ChangeSet.waiting?(@change_set)} label="Result">
          {result(row)}
        </:col>
      </.table>

      <.form_actions :if={ChangeSet.waiting?(@change_set)}>
        <.button
          id="send"
          variant={:primary}
          disabled={MapSet.size(@selected) == 0 || is_nil(@current_team.d4h_access_key)}
          phx-disable-with={if @kind == :chores, do: "Adding…", else: "Sending…"}
        >
          {if @kind == :chores,
            do: "Add #{count_chores(MapSet.size(@selected))}",
            else: "Send #{count_changes(MapSet.size(@selected))}"}
        </.button>
        <.button
          id="discard"
          type="button"
          phx-click="discard"
          data-confirm="Discard these proposed changes? Nothing is sent."
        >
          Discard changes
        </.button>
      </.form_actions>
    </.form>
    """
  end

  # One change in the glossary's words, which change when the activity starts (#595).
  defp describe(row, change_set, tz) do
    status = status(row.new_value["status"], change_set)
    times = times(row.new_value["starts_at"], row.new_value["ends_at"], tz)

    case row.action do
      :create_attendance ->
        "Add as #{status}#{times}"

      :update_attendance ->
        old = status(row.old_value["status"], change_set)

        if old == status,
          do: "New times#{times}",
          else: "#{String.capitalize(old)} to #{status}#{times}"

      :set_activity_tags ->
        tags_change(row.new_value)

      :delete_attendance ->
        old_times = times(row.old_value["starts_at"], row.old_value["ends_at"], tz)
        "Remove: #{status(row.old_value["status"], change_set)}#{old_times}"
    end
  end

  defp check(%{action: :add_chore, new_value: %{"check" => check}}), do: check
  defp check(_row), do: nil

  defp count_chores(n), do: Service.Format.count(n, one: "%d chore", many: "%d chores")

  defp tags_change(new_value) do
    [
      for(title <- new_value["titles"] || [], do: "Add #{title}"),
      for(title <- new_value["removed_titles"] || [], do: "Remove #{title}")
    ]
    |> Enum.concat()
    |> Enum.join(". ")
  end

  # Who or what a line changes: a member, or an activity for a tags line (#595).
  defp subject(%{action: :set_activity_tags} = row), do: row.new_value["activity_title"]
  defp subject(row), do: row.member && row.member.name

  defp status(nil, _change_set), do: "not listed"

  defp status(status, change_set) do
    started_at = change_set.activity && change_set.activity.started_at
    row = %{status: String.downcase(status), started_at: nil}

    case Attendance.status_word(
           row,
           %{started_at: started_at || DateTime.utc_now()},
           DateTime.utc_now()
         ) do
      :signed_up -> "signed up"
      :cant_make_it -> "can't make it"
      :no_reply -> "no reply"
      word when is_atom(word) -> Atom.to_string(word)
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

  defp result(%{status: :applied, action: :add_chore}), do: "Added, waiting on the Chores page"
  defp result(%{status: :applied}), do: "Sent"
  defp result(%{status: :skipped, error: error}), do: "Skipped. #{error}"
  defp result(%{status: :failed, error: error}), do: "Did not go through. #{error}"
  defp result(%{status: :proposed, action: :add_chore}), do: "Not added"
  defp result(%{status: :proposed}), do: "Not sent"
end
