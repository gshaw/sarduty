defmodule Web.MemberStandingLive do
  use Web, :live_view_app_layout

  import Web.Components.MemberPage

  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCheckIn
  alias App.Model.NoShow
  alias App.Model.Standing
  alias App.Operation.DeleteAwayPeriod
  alias App.Operation.DeleteCheckIn
  alias App.Operation.EndAwayPeriod
  alias App.Operation.SetGroupMember
  alias App.Operation.SetMemberNotAPerson
  alias App.Operation.SetMemberRetired
  alias App.Repo
  alias App.ViewData.MemberMilestones
  alias Web.Components.MemberSidebar

  # A member's standing (#366), and the one place a team admin changes it (#1053): Active,
  # away for a dated period, retiring, retired, or not a person, and the team's check-ins
  # with them. Away periods, check-ins, and Not a person are SAR Duty's own, never sent.
  # Retiring is the team's Retiring group (#514), so marking a member retiring adds them
  # to it, through SetGroupMember like the Groups tab. Mark as retired and Mark as
  # rejoined are D4H's retire and unretire. The tab shows only what fits the standing: a
  # bot's is the Standing section, plus any rows it already has. Adding an away period or
  # a check-in is its own page (Web.MemberStandingFormLive), so the tab reads as the
  # member's standing. Members don't see this page.
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = socket.assigns.current_team |> Member.find!(params["id"]) |> Repo.preload(:team)

    {:noreply,
     socket
     |> assign(:page_title, "#{member.name} · Standing")
     |> assign(:member, member)
     |> assign(:last_attended_at, Member.last_attended_at(member))
     |> assign(:equipment, EquipmentItem.held_by(member.team, member))
     |> assign(:attended?, Member.attended?(member))
     |> assign(:fields?, MemberSidebar.fields?(member, true))
     |> load_standing()}
  end

  def handle_event("delete-check-in", %{"id" => id}, socket) do
    message =
      case DeleteCheckIn.call(socket.assigns.current_team, id) do
        {:ok, _check_in} -> "Check-in deleted."
        :gone -> "That check-in was deleted already."
      end

    {:noreply, socket |> put_flash(:info, message) |> load_standing()}
  end

  def handle_event("end-away", %{"id" => id}, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case EndAwayPeriod.call(team, id, user) do
      {:ok, _period} ->
        {:noreply, socket |> put_flash(:info, "Away period ended.") |> load_standing()}

      :error ->
        {:noreply, put_flash(socket, :error, "Only a current away period can end early.")}

      :gone ->
        {:noreply,
         socket |> put_flash(:info, "That away period was deleted already.") |> load_standing()}
    end
  end

  def handle_event("delete-away", %{"id" => id}, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    message =
      case DeleteAwayPeriod.call(team, id, user) do
        {:ok, _period} -> "Away period deleted."
        :gone -> "That away period was deleted already."
      end

    {:noreply, socket |> put_flash(:info, message) |> load_standing()}
  end

  # No flash: the badge and the line change on the page.
  def handle_event("mark-retiring", _params, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    case SetGroupMember.add(team, member, socket.assigns.retiring_group, user, DateTime.utc_now()) do
      :ok -> {:noreply, socket |> clear_flash() |> load_standing()}
      {:error, text} -> {:noreply, socket |> load_standing() |> put_flash(:error, text)}
    end
  end

  def handle_event("unmark-retiring", _params, socket) do
    %{current_team: team, current_user: user, member: member, retiring_group: group} =
      socket.assigns

    case GroupMember.get_by(group_id: group.id, member_id: member.id) do
      # Gone already, say from another tab.
      nil ->
        {:noreply, load_standing(socket)}

      group_member ->
        case SetGroupMember.remove(team, group_member, user, DateTime.utc_now()) do
          :ok -> {:noreply, socket |> clear_flash() |> load_standing()}
          {:error, text} -> {:noreply, socket |> load_standing() |> put_flash(:error, text)}
        end
    end
  end

  # D4H's retire and unretire, on every team (#1053). SetMemberRetired refuses a member
  # who holds items, in words D4H's own refusal leaves out.
  def handle_event(event, _params, socket) when event in ["mark-retired", "mark-rejoined"] do
    %{current_team: team, current_user: user, member: member} = socket.assigns
    retired? = event == "mark-retired"

    case SetMemberRetired.call(team, member, retired?, user, DateTime.utc_now()) do
      {:ok, saved} ->
        text = if retired?, do: "retired", else: "rejoined"

        {:noreply,
         socket
         |> assign(:member, %{saved | team: member.team})
         |> put_flash(:info, "Marked #{member.name} as #{text}.")
         |> load_standing()}

      {:error, text} ->
        {:noreply, socket |> load_standing() |> put_flash(:error, text)}
    end
  end

  def handle_event(event, _params, socket) when event in ["mark-not-a-person", "mark-person"] do
    %{current_team: team, current_user: user, member: member} = socket.assigns
    not_a_person = event == "mark-not-a-person"

    {:ok, saved} = SetMemberNotAPerson.call(team, member.id, user, not_a_person)
    text = if not_a_person, do: "not a person", else: "a person"

    {:noreply,
     socket
     |> assign(:member, %{member | not_a_person: saved.not_a_person})
     |> put_flash(:info, "Marked #{member.name} as #{text}.")
     |> load_standing()}
  end

  defp load_standing(socket) do
    member = socket.assigns.member
    team = member.team
    now = DateTime.utc_now()
    today = Service.Period.today(now, team.timezone)
    periods = MemberAwayPeriod.for_member(member)
    retiring? = team |> Standing.retiring_ids() |> MapSet.member?(member.id)
    year = Service.YearRange.year_in(now, team.timezone)

    assign(socket,
      today: today,
      year: year,
      no_shows: NoShow.for_member(member, year, team.timezone),
      periods: periods,
      check_ins: MemberCheckIn.for_member(member),
      standing: Standing.of(member, periods, retiring?, today, now),
      looks_like_bot?:
        not member.not_a_person and
          Member.looks_like_not_a_person?(member, socket.assigns.attended?),
      retiring_group:
        team.retiring_d4h_group_id &&
          Group.get_by(team_id: team.id, d4h_group_id: team.retiring_d4h_group_id),
      # An away period moves the years on the team, so they load with it.
      milestones: MemberMilestones.for_member(member, now)
    )
  end

  def render(assigns) do
    ~H"""
    <.member_page
      current_member={@current_member}
      member={@member}
      tab={:standing}
      last_attended_at={@last_attended_at}
      standing={@standing}
      milestones={@milestones}
      equipment={@equipment}
      fields?={@fields?}
      maps_app={@current_user.maps_app}
      team_admin?={@team_admin?}
    >
      <section id="standing">
        <h2 class="heading">Standing</h2>
        <%!-- The answer, not an intro: body colour, not .lead's muted grey. --%>
        <p id="standing-now" class="text-lg font-semibold mb-4">{Standing.text(@standing)}</p>
        <p :if={@standing == :retired and @member.left_at} id="retired-on">
          <%!-- D4H keeps the day at 00:00 UTC; in Vancouver time it reads a day early. --%>
          {@member.name} retired on {Service.Format.date_long(DateTime.to_date(@member.left_at))}.
        </p>
        <p :if={@standing == :retiring} id="retiring-items">
          {held_text(@member, @equipment, @service)}
        </p>
        <p :if={@standing == :not_a_person} class="hint">
          A bot or a shared account. {not_a_person_rule()}
        </p>
        <%!-- One line per button, only with its button. --%>
        <p :if={@standing not in [:retired, :not_a_person]} id="retire-hint" class="hint">
          <span :if={@retiring_group}>
            Retiring members are in your {@retiring_group.title} group in {@service}. They
            can't log in to SAR Duty, and SAR Duty stops counting and contacting them.
          </span>
          Mark as retired retires them in {@service} too. They keep their attendance and
          letters, and leave the member counts.
        </p>
        <.form_actions>
          <.button
            :if={@retiring_group && @standing not in [:retired, :not_a_person, :retiring]}
            id="mark-retiring"
            type="button"
            phx-click="mark-retiring"
            phx-disable-with="Marking as retiring…"
            data-confirm={"Mark #{@member.name} as retiring? They can't log in to SAR Duty from now on. Take away their #{@service} access too."}
          >
            Mark as retiring
          </.button>
          <.button
            :if={@retiring_group && @standing == :retiring}
            id="unmark-retiring"
            type="button"
            phx-click="unmark-retiring"
            phx-disable-with="Marking as not retiring…"
            data-confirm={"Mark #{@member.name} as not retiring? They can log in to SAR Duty again, and SAR Duty counts them again."}
          >
            Mark as not retiring
          </.button>
          <.button
            :if={@standing == :not_a_person}
            id="mark-person"
            type="button"
            phx-click="mark-person"
            phx-disable-with="Marking as a person…"
            data-confirm={"Mark #{@member.name} as a person? SAR Duty counts it again and offers it when you pick people."}
          >
            Mark as a person
          </.button>
          <.button
            :if={@standing != :retired}
            id="mark-retired"
            type="button"
            variant={:danger}
            phx-click="mark-retired"
            phx-disable-with="Marking as retired…"
            data-confirm={"Mark #{@member.name} as retired today?"}
          >
            Mark as retired
          </.button>
          <.button
            :if={@standing == :retired}
            id="mark-rejoined"
            type="button"
            phx-click="mark-rejoined"
            phx-disable-with="Marking as rejoined…"
            data-confirm={"Mark #{@member.name} as rejoined? #{@service} makes them a current member again."}
          >
            Mark as rejoined
          </.button>
        </.form_actions>
      </section>

      <%!-- A bot's tab is the Standing section, and any rows it already has (#1053). --%>
      <section :if={not bot?(@standing) or @periods != []} id="away-periods" class="mt-8">
        <h2 class="heading">Away periods</h2>
        <p :if={can_add?(@standing)} class="hint">
          Time away the team knows about, such as parental leave. The member is Away until
          the last day, and sees the day they are back on Your membership, never the reason.
        </p>
        <.table
          :if={@periods != []}
          id="away-period-list"
          rows={@periods}
          row_id={&"away-period-#{&1.id}"}
          class="table-striped"
        >
          <:col :let={period} label="Reason">
            {period.reason}
          </:col>
          <:col :let={period} label="First day" class="w-px whitespace-nowrap">
            <.date_cell value={period.starts_on} timezone={@member.team.timezone} />
          </:col>
          <:col :let={period} label="Last day" class="w-px whitespace-nowrap">
            <.date_cell value={period.ends_on} timezone={@member.team.timezone} />
          </:col>
          <:col :let={period} label="" class="w-px whitespace-nowrap">
            <.button
              :if={MemberAwayPeriod.early_end(period, @today) != :error}
              id={"end-away-#{period.id}"}
              size={:sm}
              phx-click="end-away"
              phx-value-id={period.id}
              data-confirm={"End the #{period_name(period)} today? #{@member.name} is active from today."}
            >
              End away period
            </.button>
            <.button
              id={"delete-away-#{period.id}"}
              size={:sm}
              variant={:danger}
              phx-click="delete-away"
              phx-value-id={period.id}
              data-confirm={"Delete the #{period_name(period)}? It comes out of #{@member.name}'s standing."}
            >
              Delete
            </.button>
          </:col>
        </.table>
        <p :if={@periods == []} id="no-away-periods" class="text-text-muted">
          No away periods.
        </p>

        <.form_actions :if={can_add?(@standing)}>
          <.button
            id="add-away"
            navigate={~p"/teams/#{@current_team}/members/#{@member.id}/standing/away/new"}
          >
            Add away period
          </.button>
        </.form_actions>
      </section>

      <section :if={not bot?(@standing) or @check_ins != []} id="check-ins" class="mt-8">
        <h2 class="heading">Check-ins</h2>
        <p :if={can_add?(@standing)} class="hint">
          Record when you reach a member who has not been coming. It restarts their attendance
          clock. The next team admin sees who called and what they heard.
        </p>
        <.table
          :if={@check_ins != []}
          id="check-in-list"
          rows={@check_ins}
          row_id={&"check-in-#{&1.id}"}
          class="table-striped"
        >
          <:col :let={check_in} label="Date" class="w-px whitespace-nowrap">
            <.date_cell value={check_in.checked_in_on} timezone={@member.team.timezone} />
          </:col>
          <:col :let={check_in} label="What they heard">
            {check_in.note}
            <div class="text-text-muted">{check_in_by(check_in)}</div>
          </:col>
          <:col :let={check_in} label="" class="w-px whitespace-nowrap">
            <.button
              id={"delete-check-in-#{check_in.id}"}
              size={:sm}
              variant={:danger}
              phx-click="delete-check-in"
              phx-value-id={check_in.id}
              data-confirm={"Delete the check-in from #{Service.Format.date_short(check_in.checked_in_on)}? It no longer restarts #{@member.name}'s attendance clock."}
            >
              Delete
            </.button>
          </:col>
        </.table>
        <p :if={@check_ins == []} id="no-check-ins" class="text-text-muted">No check-ins yet.</p>

        <%!-- A retired member or a bot has no attendance clock to restart. --%>
        <.form_actions :if={can_add?(@standing)}>
          <.button
            id="record-check-in"
            navigate={~p"/teams/#{@current_team}/members/#{@member.id}/standing/check-ins/new"}
          >
            Record check-in
          </.button>
        </.form_actions>
      </section>

      <%!-- Team admins only: Your membership never shows a tally (#650). --%>
      <section :if={not bot?(@standing) or @no_shows != []} id="no-shows" class="mt-8">
        <h2 class="heading">No-shows</h2>
        <p class="hint">
          Activities {@member.name} signed up for and did not arrive at. Following one up
          does not restart their attendance clock.
        </p>
        <p id="no-show-count">
          {Service.Format.count(length(@no_shows), one: "%d no-show", many: "%d no-shows")} in {@year}.
        </p>
        <.table
          :if={@no_shows != []}
          id="no-show-list"
          rows={@no_shows}
          row_id={&"no-show-#{&1.id}"}
          class="table-striped"
        >
          <:col :let={no_show} label="Activity">
            <.activity_cell
              activity={no_show.activity}
              team={@current_team}
              path={~p"/teams/#{@current_team}/activities/#{no_show.activity.id}/attendance"}
            />
          </:col>
          <:col :let={no_show} label="Date" class="w-px whitespace-nowrap">
            <.date_cell activity={no_show.activity} timezone={@member.team.timezone} />
          </:col>
          <:col :let={no_show} label="Followed up">
            {no_show.note}
            <div class="text-text-muted">{no_show_followed_up(no_show, @member.team.timezone)}</div>
          </:col>
        </.table>
      </section>

      <%!-- A bot's own Mark as a person is in Standing. A retired bot's is here. --%>
      <section :if={not bot?(@standing)} id="not-a-person" class="mt-8">
        <h2 class="heading">Not a person</h2>
        <%!-- A retired bot: Retired wins the badge, so say what it still is. --%>
        <p :if={@member.not_a_person} id="still-not-a-person">
          {@member.name} is marked as not a person.
        </p>
        <p class="hint">For a bot or a shared account. {not_a_person_rule()}</p>
        <p :if={@looks_like_bot?} id="not-a-person-suggestion" class="hint mt-2">
          This looks like a bot: no email, no mobile phone, and no attendance.
        </p>
        <.form_actions>
          <.button
            :if={not @member.not_a_person}
            id="mark-not-a-person"
            type="button"
            phx-click="mark-not-a-person"
            phx-disable-with="Marking as not a person…"
            data-confirm={"Mark #{@member.name} as not a person? SAR Duty stops counting them and offering them when you pick people."}
          >
            Mark as not a person
          </.button>
          <.button
            :if={@member.not_a_person}
            id="mark-person"
            type="button"
            phx-click="mark-person"
            phx-disable-with="Marking as a person…"
            data-confirm={"Mark #{@member.name} as a person? SAR Duty counts it again and offers it when you pick people."}
          >
            Mark as a person
          </.button>
        </.form_actions>
      </section>
    </.member_page>
    """
  end

  # "Avery Chen holds 3 items. Get them back …" The Equipment tab lists them. D4H refuses
  # to retire a member who holds any (#1053), and only its web app moves an item.
  defp held_text(member, [], _service), do: "#{member.name} holds no items."

  defp held_text(member, [_item], service),
    do:
      "#{member.name} holds 1 item. Get it back and move it in #{service} before you retire them."

  defp held_text(member, equipment, service),
    do:
      "#{member.name} holds #{length(equipment)} items. Get them back and move them in #{service} before you retire them."

  # What Not a person means, under both its buttons.
  defp not_a_person_rule,
    do:
      "It logs in and gets email like any member, as a team admin if it has that access. SAR Duty never counts it or offers it when you pick people."

  defp bot?(standing), do: standing == :not_a_person

  # Whether the member can get an away period or a check-in: AddAwayPeriod and
  # RecordCheckIn refuse the rest.
  defp can_add?(standing), do: standing not in [:not_a_person, :retired]

  # "away period from Sep 8, 2026 (Parental leave)", for a confirmation that names it.
  defp period_name(period),
    do: "away period from #{Service.Format.date_short(period.starts_on)} (#{period.reason})"

  defp no_show_followed_up(%{followed_up_at: nil}, _timezone), do: "Not followed up"

  defp no_show_followed_up(no_show, timezone) do
    by = if no_show.followed_up_by_user, do: " by #{no_show.followed_up_by_user.email}"
    "Followed up#{by}, #{Service.Format.date_short(no_show.followed_up_at, timezone)}"
  end

  defp check_in_by(%{user: %{email: email}}), do: "Recorded by #{email}"
  defp check_in_by(_check_in), do: "Recorded by a team admin"
end
