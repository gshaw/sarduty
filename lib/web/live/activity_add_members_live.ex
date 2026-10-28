defmodule Web.ActivityAddMembersLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Group
  alias App.Model.Member
  alias App.Model.Standing
  alias App.Operation.InviteMembers
  alias Service.Format

  # Adding members to an activity as No reply (#564), by name or by group, laid out like
  # Apply a template. Each pick joins one To add list; InviteMembers.plan/3 decides who
  # goes and names who a group leaves out. Adding emails nobody. Only before the start,
  # on an activity neither deleted nor published.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    activity = Web.ActivityLive.fetch_activity(team, id)
    now = DateTime.utc_now()

    case Activity.adding(activity, true, now) do
      :open ->
        socket =
          socket
          |> assign(page_title: "Add members", activity: activity, picks: [])
          |> assign(
            on_activity: InviteMembers.on_activity(activity),
            away: InviteMembers.away(team, activity),
            members: people(team, now),
            groups: Group.get_all(team.id),
            day: Format.month_day(activity.started_at, team.timezone)
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

  defp leave(socket, activity, now) do
    text =
      if Activity.started?(activity, now),
        do: "The activity has started, so nobody can be added.",
        else: "Published, so nobody can be added. #{D4H.unpublish_text(activity.team)}"

    socket
    |> put_flash(:error, text)
    |> push_navigate(to: ~p"/teams/#{socket.assigns.current_team}/activities/#{activity.id}")
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
        <form id="add-member-form" phx-submit="add-member">
          <.input
            type="combobox"
            name="member-id"
            id="member-id"
            label="Add a member"
            value=""
            prompt="Select a member"
            options={@member_options}
          />
          <.button id="add-member">Add member</.button>
        </form>
        <form id="add-group-form" phx-submit="add-group" class="mt-6">
          <.input
            type="combobox"
            name="group-id"
            id="group-id"
            label="Add a group"
            value=""
            prompt="Select a group"
            options={@group_options}
          />
          <.button id="add-group">Add group</.button>
        </form>
        <p class="hint mt-4">
          A group adds its members who are not retired. Anyone away on {@day} is left out.
        </p>
      </aside>

      <main class="content-2/3">
        <section id="members-to-add">
          <h2 class="heading">To add</h2>
          <p :if={@to_add == []} id="members-nothing-to-add" class="hint">
            Add members by name, or a group. Then add them to the activity.
          </p>
          <.table
            :if={@to_add != []}
            id="members-to-add-table"
            rows={@to_add}
            row_id={fn {_reason, member} -> "to-add-#{member.id}" end}
            class="table-striped"
          >
            <:col :let={{reason, member}} label="Member">
              {member.name}
              <div class="hint">{InviteMembers.reason_text(reason)}</div>
            </:col>
            <:col :let={{_reason, member}} label="" class="w-px whitespace-nowrap">
              <.button
                id={"remove-#{member.id}"}
                type="button"
                size={:sm}
                phx-click="remove"
                phx-value-id={member.id}
              >
                Remove
              </.button>
            </:col>
          </.table>
          <p :if={@plan.on_activity != []} id="left-out-on-activity" class="mt-4">
            On the activity already, so left out: {names(@plan.on_activity)}.
          </p>
          <p :if={@plan.away != []} id="left-out-away" class="mt-4">
            Away on {@day}, so left out: {names(@plan.away)}. Add them by name to include them.
          </p>
          <form :if={@to_add != []} id="members-add-form" phx-submit="add" class="mt-4">
            <p class="hint">They show as No reply until they answer. SAR Duty emails nobody.</p>
            <.form_actions>
              <.button id="members-send" variant={:success} phx-disable-with="Adding…">
                {Format.count(length(@to_add), one: "Add 1 member", many: "Add %d members")}
              </.button>
            </.form_actions>
          </form>
        </section>
      </main>
    </div>
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

  def handle_event("add-group", %{"group-id" => id}, socket) do
    %{current_team: team} = socket.assigns
    group = Group.find!(team, id)
    add_picks(socket, InviteMembers.group_picks(team, [group], DateTime.utc_now()))
  end

  def handle_event("remove", %{"id" => id}, socket) do
    picks = Enum.reject(socket.assigns.picks, &(Integer.to_string(elem(&1, 1).id) == id))
    {:noreply, socket |> assign(picks: picks) |> assign_plan(DateTime.utc_now())}
  end

  def handle_event("add", _params, socket) do
    %{current_team: team, current_user: user, activity: activity, picks: picks} = socket.assigns

    case InviteMembers.call(team, activity, picks, user, :invite, DateTime.utc_now()) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(flash_kind(result.rows), result_text(result))
         |> push_navigate(to: ~p"/teams/#{team}/activities/#{activity.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, InviteMembers.error_text(team, reason))}
    end
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
