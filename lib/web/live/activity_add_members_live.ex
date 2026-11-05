defmodule Web.ActivityAddMembersLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Group
  alias App.Model.Member
  alias App.Model.Standing
  alias App.Operation.InviteMembers
  alias Service.Format

  # Adding members to an activity (#564), by name or by group, laid out like Apply a
  # template. A pick lists its members at once, checked, under Not added yet (#905);
  # InviteMembers.plan/3 decides who is listed and names who a group leaves out. Only
  # the checked rows are added, and only by the Add button. Adding emails nobody. Until
  # it's published, on an activity not deleted: as No reply before the start, and as
  # attended after it (#766).
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    activity = Web.ActivityLive.fetch_activity(team, id)
    now = DateTime.utc_now()

    case Activity.adding(activity, true, now) do
      :open ->
        members = people(team, now)

        socket =
          socket
          |> assign(page_title: "Add members", activity: activity, picks: [])
          |> assign(unchecked: MapSet.new(), group_picks: 0)
          |> assign(
            on_activity: InviteMembers.on_activity(activity),
            away: InviteMembers.away(team, activity),
            members: members,
            standings: Standing.by_member(team, members, now),
            groups: Group.get_all(team.id),
            day: Format.month_day(activity.started_at, team.timezone),
            started?: Activity.started?(activity, now)
          )
          |> assign_plan(now)

        {:ok, socket}

      _closed ->
        {:ok, leave(socket, activity, now)}
    end
  end

  # A stale visitor goes back to the activity, as a deleted activity's pages do.
  defp leave(socket, %Activity{deleted_at: %DateTime{}} = activity, _now),
    do: Web.ActivityLive.leave_deleted(socket, activity)

  defp leave(socket, activity, _now) do
    socket
    |> put_flash(
      :error,
      "Published, so nobody can be added. #{D4H.unpublish_text(activity.team)}"
    )
    |> push_navigate(
      to: ~p"/teams/#{socket.assigns.current_team}/activities/#{activity.id}/members"
    )
  end

  # Who the name picker offers: current members SAR Duty counts, A to Z.
  defp people(team, now) do
    retiring = Standing.retiring_ids(team)

    team.id
    |> Member.get_all()
    |> Enum.filter(&(Member.current?(&1, now) and Member.counted?(&1, retiring)))
  end

  defp assign_plan(socket, now) do
    %{activity: activity, picks: picks, on_activity: on_activity, away: away} = socket.assigns
    plan = InviteMembers.plan(activity, picks, %{on_activity: on_activity, away: away, now: now})

    assign(socket,
      plan: plan,
      to_add: Enum.sort_by(plan.add, &String.downcase(elem(&1, 1).name)),
      checked:
        Enum.count(plan.add, &(not MapSet.member?(socket.assigns.unchecked, elem(&1, 1).id))),
      member_options: member_options(socket.assigns.members, plan.add, on_activity),
      group_options: for(g <- socket.assigns.groups, do: {g.title, g.id})
    )
  end

  # Everyone not listed or on the activity. Someone a group left out for being away can
  # still be added by name.
  defp member_options(members, add, on_activity) do
    listed = MapSet.new(on_activity ++ Enum.map(add, &elem(&1, 1).id))
    for m <- members, not MapSet.member?(listed, m.id), do: {m.name, m.id}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item label={@activity.ref_id} path={~p"/teams/#{@current_team}/activities/#{@activity.id}"} />
      <:item label="Add members" />
    </.breadcrumbs>
    <h1 class="title">Add members</h1>
    <p class="lead">
      {@activity.title} · {Format.datetime_medium(@activity.started_at, @current_team.timezone)}
    </p>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <%!-- A pick lists its members at once: no button, so nothing reads as added. --%>
        <form id="add-member-form" phx-change="add-member" phx-submit="add-member">
          <.input
            type="combobox"
            name="member-id"
            id="member-id"
            label="Find a member"
            value=""
            prompt="Select a member"
            options={@member_options}
          />
        </form>
        <%!-- A new id after each pick starts the combobox again, empty: its options don't
        change, so nothing else would clear the group just picked. --%>
        <form id="add-group-form" phx-change="add-group" phx-submit="add-group">
          <.input
            type="combobox"
            name="group-id"
            id={"group-id-#{@group_picks}"}
            label="Find a group"
            value=""
            prompt="Select a group"
            options={@group_options}
          />
        </form>
        <p class="hint mt-4">
          A group lists its members who are not retired. Anyone away on {@day} is left out.
        </p>
      </aside>

      <main class="content-2/3">
        <section id="members-to-add">
          <p :if={@to_add == []} id="members-nothing-to-add" class="hint">
            Find a member or a group. They stay under Not added yet, checked, until you add them.
          </p>
          <form
            :if={@to_add != []}
            id="members-add-form"
            phx-change="tick"
            phx-submit="add"
          >
            <.table
              id="members-to-add-table"
              rows={@to_add}
              row_id={fn {_reason, member} -> "to-add-#{member.id}" end}
              class="table-striped w-fit"
            >
              <:col :let={{_reason, member}} label="" class="w-px" select_all>
                <input
                  type="checkbox"
                  id={"add-select-#{member.id}"}
                  name="member_ids[]"
                  value={member.id}
                  checked={not MapSet.member?(@unchecked, member.id)}
                />
              </:col>
              <%!-- No link: leaving the page drops the list. --%>
              <:col :let={{reason, member}} label="Not added yet">
                <.member_cell
                  member={member}
                  team={@current_team}
                  standing={@standings[member.id]}
                  link={false}
                  label_for={"add-select-#{member.id}"}
                />
                <div class="hint">{InviteMembers.reason_text(reason)}</div>
              </:col>
            </.table>
            <.left_out plan={@plan} day={@day} />
            <p :if={!@started?} class="hint mt-4">
              They show as No reply until they answer. SAR Duty emails nobody.
            </p>
            <p :if={@started?} id="members-add-attended" class="hint mt-4">
              They're added as attended, with the activity's times, {Format.time_short(
                @activity.started_at,
                @current_team.timezone
              )} to {Format.time_short(@activity.finished_at, @current_team.timezone)}. SAR Duty emails nobody.
            </p>
            <.form_actions>
              <.button
                id="members-send"
                variant={:success}
                disabled={@checked == 0}
                phx-disable-with="Adding…"
              >
                {Format.count(@checked, one: "Add 1 member", many: "Add %d members")}
              </.button>
              <.button
                id="members-cancel"
                navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}/members"}
              >
                Cancel
              </.button>
            </.form_actions>
          </form>
          <.left_out :if={@to_add == []} plan={@plan} day={@day} />
        </section>
      </main>
    </div>
    """
  end

  attr :plan, :map, required: true
  attr :day, :string, required: true

  # Who the picks left out, under the list, or alone once nobody is listed.
  defp left_out(assigns) do
    ~H"""
    <p :if={@plan.on_activity != []} id="left-out-on-activity" class="mt-4">
      On the activity already, so left out: {names(@plan.on_activity)}.
    </p>
    <p :if={@plan.away != []} id="left-out-away" class="mt-4">
      Away on {@day}, so left out: {names(@plan.away)}. Find them by name to include them.
    </p>
    """
  end

  # A few names, or a count once the list runs long.
  @names 5

  defp names(members) when length(members) > @names, do: count_members(length(members))
  defp names(members), do: members |> Enum.map(& &1.name) |> Format.and_list()

  def handle_event("add-member", %{"member-id" => ""}, socket), do: {:noreply, socket}

  # Ids come from the browser, so each is looked up through the team.
  def handle_event("add-member", %{"member-id" => id}, socket) do
    member = Member.find!(socket.assigns.current_team, id)
    add_picks(socket, [{:name, member}])
  end

  def handle_event("add-group", %{"group-id" => ""}, socket), do: {:noreply, socket}

  # A group checks its members again, even ones unchecked before.
  def handle_event("add-group", %{"group-id" => id}, socket) do
    %{current_team: team} = socket.assigns
    group = Group.find!(team, id)
    picks = InviteMembers.group_picks(team, [group], DateTime.utc_now())
    unchecked = MapSet.difference(socket.assigns.unchecked, MapSet.new(picks, &elem(&1, 1).id))

    socket
    |> assign(unchecked: unchecked, group_picks: socket.assigns.group_picks + 1)
    |> add_picks(picks)
  end

  # The listed rows left unchecked, kept so a re-render never checks them again.
  def handle_event("tick", params, socket) do
    {:noreply,
     socket |> assign(unchecked: unchecked(socket, params)) |> assign_plan(DateTime.utc_now())}
  end

  # Only the checked rows' picks go; plan/3 drops a member with no pick left.
  def handle_event("add", params, socket) do
    unchecked = unchecked(socket, params)
    %{current_team: team, current_user: user, activity: activity} = socket.assigns
    picks = Enum.reject(socket.assigns.picks, &MapSet.member?(unchecked, elem(&1, 1).id))

    case InviteMembers.call(team, activity, picks, user, :invite, DateTime.utc_now()) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(flash_kind(result.rows), result_text(result))
         |> push_navigate(to: ~p"/teams/#{team}/activities/#{activity.id}/members")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, InviteMembers.error_text(team, reason))}
    end
  end

  # Ids come from the browser, so only the listed rows count.
  defp unchecked(socket, params) do
    checked = MapSet.new(params["member_ids"] || [])
    listed = for {_reason, m} <- socket.assigns.to_add, do: m.id
    MapSet.new(for id <- listed, not MapSet.member?(checked, Integer.to_string(id)), do: id)
  end

  defp add_picks(socket, new) do
    picks = socket.assigns.picks ++ new
    {:noreply, socket |> assign(picks: picks) |> assign_plan(DateTime.utc_now())}
  end

  defp flash_kind(rows),
    do: if(Enum.any?(rows, &(&1.status == :failed)), do: :error, else: :info)

  @doc """
  What adding did, from InviteMembers.call/6's result: "3 members added. Nobody was
  emailed.", or the count and then each row that did not go, with why. Who the page
  named as left out is not named again.
  """
  def result_text(%{rows: rows}) do
    case InviteMembers.result_lines(rows) do
      [added] when rows != [] -> "#{added} Nobody was emailed."
      lines -> Enum.join(lines, " ")
    end
  end

  defp count_members(n), do: Format.count(n, one: "%d member", many: "%d members")
end
