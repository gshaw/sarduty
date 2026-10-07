defmodule Web.ActivityAttendanceLive do
  use Web, :live_view_app_layout

  import Web.Components.AttendanceTable

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Operation.ApplyAttendanceImport

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    activity = Activity.find!(socket.assigns.current_team, params["id"])

    if Activity.deleted?(activity),
      do: {:noreply, Web.ActivityLive.leave_deleted(socket, activity)},
      else: load(socket, activity)
  end

  defp load(socket, activity) do
    d4h = D4H.build_context_from_team(socket.assigns.current_team)
    team_members = D4H.fetch_team_members(d4h)

    attendance_records =
      D4H.fetch_activity_attendance(d4h, activity.d4h_activity_id, team_members)

    socket =
      assign(socket,
        page_title: "Import attendance",
        activity: activity,
        team_members: team_members,
        attendance_records: attendance_records,
        recommendations: nil,
        import_content: ""
      )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        label={"#{@activity.ref_id}"}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label="Import attendance" />
    </.breadcrumbs>
    <h1 class="title">{@activity.title}</h1>

    <%= if @activity.is_published do %>
      <p>
        Attendance cannot be changed. The activity is published in D4H.
      </p>
    <% else %>
      <%= if @recommendations == nil do %>
        <h2 class="heading mt-p">Import attendance</h2>
        <p>
          Change D4H attendance to match a SAR Assist attendance report.
          SAR Assist exports the report after members use its QR code.
          See an <a
            target="_blank"
            class="link"
            href="https://gist.github.com/gshaw/ce675c595cd3b765dcee1eda081e1e6d"
          >example attendance report</a>.
        </p>
        <form phx-submit="import-attendance">
          <.input
            type="textarea"
            name="import_content"
            value={@import_content}
            label="Attendance report"
            class="h-[16rem]"
          >
            Paste the attendance report here.
            SAR Duty matches members by their name, email, or phone in D4H.
            You review the changes before SAR Duty makes them.
          </.input>
          <.button variant={:success}>Import attendance</.button>
        </form>
      <% else %>
        <h2 class="heading">Recommended changes</h2>
        <form phx-submit="perform-recommendations" _phx-change="validate-recommendations">
          <.table id="recommendations" rows={@recommendations} class="table-striped table-stack">
            <:col :let={{_op, attendance_id, _member}} label="" class="stack-check">
              <.input :if={attendance_id} type="checkbox" name={attendance_id} checked />
            </:col>
            <:col :let={{op, _, _}} label="" class="stack-full">
              <%= if op == :not_invited do %>
                <.badge kind={:danger}>Not signed up</.badge>
              <% else %>
                <%= if op == :add do %>
                  <span class="text-success-1 font-bold">Add</span>
                <% else %>
                  <span class="text-danger-1 font-bold">Remove</span>
                <% end %>
              <% end %>
            </:col>
            <:col :let={{_, _, member}} label="Name" class="stack-title">{member.name}</:col>
            <:col :let={{_, _, member}} label="Email" class="stack-full break-all">
              {member.email}
            </:col>
            <:col :let={{_, _, member}} label="Phone">{member.phone}</:col>
          </.table>
          <.form_actions class="mt-4">
            <.button disabled={disable_perform_recommendations?(@recommendations)} variant={:success}>
              Perform checked changes
            </.button>
            <.button type="button" phx-click="reset">Start over</.button>
          </.form_actions>
        </form>
      <% end %>
    <% end %>

    <h2 class="heading mt-p">Current attendance</h2>
    <.attendance_table attendance_records={@attendance_records} status="attending" />
    """
  end

  def disable_perform_recommendations?(recommendations) do
    !Enum.any?(recommendations, fn {op, _, _} ->
      op == :add || op == :remove
    end)
  end

  def operation_css_class(:unknown), do: "text-danger-1"
  def operation_css_class(_), do: ""
  def operation_description(:add), do: "Add"
  def operation_description(:remove), do: "Remove"
  def operation_description(:unknown), do: "Unknown"

  def handle_event("import-attendance", %{"import_content" => import_content}, socket) do
    d4h_activity_id = socket.assigns.activity.d4h_activity_id
    d4h = D4H.build_context_from_team(socket.assigns.current_team)
    team_members = D4H.fetch_team_members(d4h)
    attendance_records = D4H.fetch_activity_attendance(d4h, d4h_activity_id, team_members)
    recommendations = fetch_recommendations(import_content, attendance_records)

    socket =
      assign(socket,
        import_content: import_content,
        team_members: team_members,
        attendance_records: attendance_records,
        recommendations: recommendations
      )

    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    socket =
      assign(socket,
        recommendations: nil,
        import_content: ""
      )

    {:noreply, socket}
  end

  def handle_event("perform-recommendations", params, socket) do
    %{current_team: team, activity: activity, current_user: user} = socket.assigns

    attendance_ids =
      for {key, "true"} <- params, {id, ""} <- [Integer.parse(key)], into: MapSet.new(), do: id

    changes = selected_changes(socket.assigns, attendance_ids)

    socket =
      if changes == [], do: socket, else: apply_import(socket, team, activity, user, changes)

    d4h = D4H.build_context_from_team(team)

    new_recommendations =
      Enum.reject(socket.assigns.recommendations, fn {_, id, _} ->
        MapSet.member?(attendance_ids, id)
      end)

    new_attendance_records =
      D4H.fetch_activity_attendance(d4h, activity.d4h_activity_id, socket.assigns.team_members)

    {:noreply,
     assign(socket,
       attendance_records: new_attendance_records,
       recommendations: new_recommendations
     )}
  end

  defp apply_import(socket, team, activity, user, changes) do
    case ApplyAttendanceImport.call(team, activity, user, changes, DateTime.utc_now()) do
      {:ok, results} -> show_results(socket, results)
      {:error, error} -> put_flash(socket, :error, error_text(error))
    end
  end

  defp selected_changes(assigns, attendance_ids) do
    records = Map.new(assigns.attendance_records, &{&1.d4h_attendance_id, &1})

    for {action, id, member} <- assigns.recommendations,
        action in [:add, :remove],
        MapSet.member?(attendance_ids, id),
        record <- List.wrap(records[id]) do
      %{
        action: action,
        d4h_attendance_id: id,
        d4h_member_id: member.d4h_member_id,
        status: record.status,
        name: member.name
      }
    end
  end

  defp show_results(socket, results) do
    failures =
      for {change, %{status: status, error: error}} <- results,
          status != :applied,
          do: "#{change.name}: #{error}"

    case failures do
      [] ->
        put_flash(socket, :info, "#{count_changes(length(results))} saved to D4H.")

      _ ->
        put_flash(
          socket,
          :error,
          "#{count_changes(length(failures))} did not go through. #{Enum.join(failures, " ")}"
        )
    end
  end

  defp count_changes(count),
    do: Service.Format.count(count, one: "%d attendance change", many: "%d attendance changes")

  defp error_text(:published),
    do: "Attendance cannot be changed once the activity is published. Unpublish it in D4H first."

  defp error_text(:deleted), do: "This activity is deleted in D4H. Nothing can be sent to it."
  defp error_text(:no_team_key), do: "Save the team's D4H access key in Team settings first."
  defp error_text(error), do: "D4H did not answer. Try again. #{Exception.message(error)}"

  def parse_import_content(import_content) do
    import_content
    |> String.split("\n")
    |> List.delete_at(0)
    |> Enum.map(&String.trim(&1))
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      [_group, name, email, phone | _] = String.split(line, "\t")

      %{
        name: String.trim(name),
        email: String.trim(email),
        phone: String.trim(phone)
      }
    end)
  end

  def normalize_phone(phone), do: Regex.replace(~r/[^\d]/, phone || "", "")
  def phone_equal?(a, b), do: downcase_equal?(normalize_phone(a), normalize_phone(b))

  def downcase_equal?(a, b) do
    a = trim_and_downcase(a || "")
    b = trim_and_downcase(b || "")
    if a == "" || b == "", do: false, else: a == b
  end

  def trim_and_downcase(value) do
    value |> String.trim() |> String.downcase()
  end

  def member_equal?(a, b) do
    downcase_equal?(a.email, b.email) ||
      downcase_equal?(a.name, b.name) ||
      phone_equal?(a.phone, b.phone)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  def fetch_recommendations(import_content, attendance_records) do
    attended_members = parse_import_content(import_content)

    # unknown_recommendations =
    #   Enum.reject(attended_members, fn attended_member ->
    #     Enum.any?(team_members, &member_equal?(&1, attended_member))
    #   end)
    #   |> Enum.map(&{:unknown, nil, &1})

    # find any attended_member that isn't in attendance records
    not_invited_recommendations =
      attended_members
      |> Enum.reject(fn attended_member ->
        # all invited (and thus known) attended members
        Enum.any?(attendance_records, fn r -> member_equal?(r.member, attended_member) end)
      end)
      |> Enum.map(&{:not_invited, nil, &1})

    attendance_recommendations =
      attendance_records
      |> Enum.map(fn attendance ->
        is_attending = attendance.status == "attending"
        did_attend = Enum.any?(attended_members, &member_equal?(&1, attendance.member))

        operation =
          case {is_attending, did_attend} do
            {true, false} -> :remove
            {false, true} -> :add
            _ -> :noop
          end

        {operation, attendance.d4h_attendance_id, attendance.member}
      end)
      |> Enum.reject(fn {op, _, _} -> op == :noop end)
      |> Enum.sort(fn {op1, _, m1}, {op2, _, m2} ->
        if op1 == op2, do: m1.name < m2.name, else: op1 < op2
      end)

    attendance_recommendations ++ not_invited_recommendations
  end
end
