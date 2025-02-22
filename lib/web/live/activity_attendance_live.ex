defmodule Web.ActivityAttendanceLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Activity

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    activity = Activity.get(params["id"])
    d4h = D4H.build_context_from_user(socket.assigns.current_user)
    team_members = D4H.fetch_team_members(d4h)

    attendance_records =
      D4H.fetch_activity_attendance(d4h, activity.d4h_activity_id, team_members)

    socket =
      assign(socket,
        page_title: "Attendance",
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
      <:item label="Activities" path={~p"/#{@current_team.subdomain}/activities"} />
      <:item
        label={"##{@activity.ref_id}"}
        path={~p"/#{@current_team.subdomain}/activities/#{@activity.id}"}
      />
      <:item label="Attendance" />
    </.breadcrumbs>
    <h1 class="title">{@activity.title}</h1>

    <%= if @activity.is_published do %>
      <p>
        Attendance cannot be modified because activity is published.
      </p>
    <% else %>
      <%= if @recommendations == nil do %>
        <h2 class="heading mt-p">Import Attendance</h2>
        <p>
          Synchronize D4H attendance from SAR Assist.
          Attendance report is exported by SAR Assist after using QR code check in process.
          View an <a
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
            label="Attendance record report"
            class="h-[16rem]"
          >
            Copy and paste the attendance report into this text area.
            Members will be matched by their name, email, or phone in D4H.
            You will have a chance to review changes before they are performed.
          </.input>
          <.button class="btn-success">Import Attendance Report</.button>
        </form>
      <% else %>
        <h2 class="heading">Recommended changes</h2>
        <form phx-submit="perform-recommendations" _phx-change="validate-recommendations">
          <.table id="recommendations" rows={@recommendations} class="table-striped">
            <:col :let={{_op, attendance_id, _member}} label="">
              <.input :if={attendance_id} type="checkbox" name={attendance_id} checked />
            </:col>
            <:col :let={{op, _, _}} label="">
              <%= if op == :not_invited do %>
                <span class="text-danger-content font-bold bg-danger-1 rounded px-2 py-1">
                  Not Invited
                </span>
              <% else %>
                <%= if op == :add do %>
                  <span class="text-success-1 font-bold">Add</span>
                <% else %>
                  <span class="text-danger-1 font-bold">Remove</span>
                <% end %>
              <% end %>
            </:col>
            <:col :let={{_, _, member}} label="Name">{member.name}</:col>
            <:col :let={{_, _, member}} label="Email">{member.email}</:col>
            <:col :let={{_, _, member}} label="Phone">{member.phone}</:col>
          </.table>
          <.form_actions class="mt-4">
            <.button disabled={disable_perform_recommendations?(@recommendations)} class="btn-success">
              Perform Checked Recommendations
            </.button>
            <.a class="btn" phx-click="reset">
              Reset
            </.a>
          </.form_actions>
        </form>
      <% end %>
    <% end %>

    <h2 class="heading mt-p">Current Attendance</h2>
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
    d4h = D4H.build_context_from_user(socket.assigns.current_user)
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

  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  def handle_event("perform-recommendations", params, socket) do
    attendance_ids =
      Enum.reduce(params, [], fn {k, v}, a ->
        if v == "true", do: [String.to_integer(k) | a], else: a
      end)

    recommendations =
      socket.assigns.recommendations
      |> Enum.filter(fn {_, id, _} -> id != nil && Enum.member?(attendance_ids, id) end)

    d4h = D4H.build_context_from_user(socket.assigns.current_user)

    for {op, attendance_id, _member} <- recommendations do
      case op do
        :add ->
          D4H.add_attendance(d4h, attendance_id)

        :remove ->
          D4H.remove_attendance(d4h, attendance_id)

        _ ->
          nil
      end
    end

    new_recommendations =
      socket.assigns.recommendations
      |> Enum.reject(fn {_, attendance_id, _} -> Enum.member?(attendance_ids, attendance_id) end)

    new_attendance_records =
      D4H.fetch_activity_attendance(
        d4h,
        socket.assigns.activity.d4h_activity_id,
        socket.assigns.team_members
      )

    socket =
      assign(
        socket,
        attendance_records: new_attendance_records,
        recommendations: new_recommendations
      )

    {:noreply, socket}
  end

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
