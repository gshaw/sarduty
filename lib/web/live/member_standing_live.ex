defmodule Web.MemberStandingLive do
  use Web, :live_view_app_layout

  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCheckIn
  alias App.Operation.AddAwayPeriod
  alias App.Operation.DeleteAwayPeriod
  alias App.Operation.DeleteCheckIn
  alias App.Operation.EndAwayPeriod
  alias App.Operation.RecordCheckIn
  alias App.Repo
  alias App.ViewData.MemberMilestones
  alias Web.Components.NotAPersonSwitch
  alias Web.Components.Standing

  # A member's standing (#366): Active, away for a dated period, or not a person, and the
  # team's check-ins with them. SAR Duty's own data, never sent to D4H, and members don't
  # see it.
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
     |> assign(:equipment, held(member))
     |> load_standing()
     |> assign_new_form()}
  end

  def handle_event("validate-away", %{"away" => params}, socket) do
    changeset =
      %MemberAwayPeriod{}
      |> MemberAwayPeriod.build_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :away_form, to_form(changeset, as: "away"))}
  end

  def handle_event("add-away", %{"away" => params}, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    case AddAwayPeriod.call(team, member.id, user, params) do
      {:ok, _period} ->
        {:noreply,
         socket |> put_flash(:info, "Away period added.") |> load_standing() |> assign_new_form()}

      {:error, changeset} ->
        {:noreply, assign(socket, :away_form, to_form(changeset, as: "away"))}

      :not_a_person ->
        {:noreply, put_flash(socket, :error, "Turn off Not a person to add an away period.")}

      :retired ->
        {:noreply, put_flash(socket, :error, "Retired members get no away periods.")}
    end
  end

  def handle_event("validate-check-in", %{"check_in" => params}, socket) do
    changeset =
      %MemberCheckIn{}
      |> MemberCheckIn.build_changeset(params, socket.assigns.today)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :check_in_form, to_form(changeset, as: "check_in"))}
  end

  def handle_event("check-in", %{"check_in" => params}, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    case RecordCheckIn.call(team, member.id, user, params) do
      {:ok, _check_in} ->
        {:noreply,
         socket
         |> put_flash(:info, "Check-in recorded.")
         |> load_standing()
         |> assign_new_form()}

      {:error, changeset} ->
        {:noreply, assign(socket, :check_in_form, to_form(changeset, as: "check_in"))}
    end
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

  def handle_info({:not_a_person_changed, not_a_person}, socket) do
    member = %{socket.assigns.member | not_a_person: not_a_person}
    {:noreply, socket |> assign(:member, member) |> load_standing()}
  end

  defp load_standing(socket) do
    member = socket.assigns.member
    now = DateTime.utc_now()
    today = Service.Period.today(now, member.team.timezone)
    periods = MemberAwayPeriod.for_member(member)

    assign(socket,
      today: today,
      periods: periods,
      check_ins: MemberCheckIn.for_member(member),
      standing: MemberAwayPeriod.standing(member, periods, today, now),
      # An away period moves the years on the team, so they load with it.
      milestones: MemberMilestones.for_member(member, now)
    )
  end

  defp assign_new_form(socket) do
    changeset =
      MemberAwayPeriod.build_changeset(%MemberAwayPeriod{starts_on: socket.assigns.today})

    check_in =
      MemberCheckIn.build_changeset(
        %MemberCheckIn{checked_in_on: socket.assigns.today},
        %{},
        socket.assigns.today
      )

    socket
    |> assign(:away_form, to_form(changeset, as: "away"))
    |> assign(:check_in_form, to_form(check_in, as: "check_in"))
  end

  def render(assigns) do
    ~H"""
    <.member_head member={@member} last_attended_at={@last_attended_at} standing={@standing} />
    <.member_tabs member={@member} active_tab={:standing} />
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content
          member={@member}
          maps_app={@current_user.maps_app}
          milestones={@milestones}
          equipment={@equipment}
        />
      </aside>
      <main class="content-2/3">
        <section id="standing">
          <h2 class="heading">Standing</h2>
          <p id="standing-now" class="lead">{Standing.text(@standing)}</p>
          <p class="hint">
            Active unless the member is away or not a person. SAR Duty keeps it, and
            nothing here goes to D4H. A member away sees when they're back on Your
            membership, never the reason.
          </p>
        </section>

        <section id="away-periods" class="mt-8">
          <h2 class="heading">Away periods</h2>
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
              {Service.Format.date_short(period.starts_on)}
            </:col>
            <:col :let={period} label="Last day" class="w-px whitespace-nowrap">
              {Service.Format.date_short(period.ends_on)}
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

          <p :if={@standing == :not_a_person} id="away-not-a-person" class="hint mt-6">
            Turn off Not a person to add an away period.
          </p>
          <p :if={@standing == :retired} id="away-retired" class="hint mt-6">
            Retired members get no away periods.
          </p>
          <.form
            :if={@standing not in [:not_a_person, :retired]}
            for={@away_form}
            id="away-form"
            phx-change="validate-away"
            phx-submit="add-away"
            class="measure mt-6"
          >
            <h3 class="subheading">Add an away period</h3>
            <.error_summary form={@away_form} />
            <div class="grid md:grid-cols-2 gap-x-6">
              <.input field={@away_form[:starts_on]} type="date" label="First day" />
              <.input field={@away_form[:ends_on]} type="date" label="Last day" />
            </div>
            <.input field={@away_form[:reason]} label="Reason" maxlength="60">
              For example, Parental leave or Moving. Leave out medical details.
            </.input>
            <.form_actions>
              <.button variant={:success}>Add away period</.button>
            </.form_actions>
          </.form>
        </section>

        <section id="check-ins" class="mt-8">
          <h2 class="heading">Check-ins</h2>
          <p class="hint">
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
            <:col :let={check_in} label="Day" class="w-px whitespace-nowrap">
              {Service.Format.date_short(check_in.checked_in_on)}
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

          <.form
            for={@check_in_form}
            id="check-in-form"
            phx-change="validate-check-in"
            phx-submit="check-in"
            class="measure mt-6"
          >
            <h3 class="subheading">Record a check-in</h3>
            <.error_summary form={@check_in_form} />
            <.input field={@check_in_form[:checked_in_on]} type="date" label="Day you reached them" />
            <.input
              field={@check_in_form[:note]}
              type="textarea"
              label="What you heard (optional)"
            />
            <.form_actions>
              <.button variant={:success}>Record check-in</.button>
            </.form_actions>
          </.form>
        </section>

        <section id="not-a-person-section" class="mt-8">
          <.live_component
            module={NotAPersonSwitch}
            id="not-a-person"
            member={@member}
            user={@current_user}
          />
        </section>
      </main>
    </div>
    """
  end

  # "away period from Sep 8, 2026 (Parental leave)", for a confirmation that names it.
  defp period_name(period),
    do: "away period from #{Service.Format.date_short(period.starts_on)} (#{period.reason})"

  defp check_in_by(%{user: %{email: email}}), do: "Recorded by #{email}"
  defp check_in_by(_check_in), do: "Recorded by a team admin"
end
