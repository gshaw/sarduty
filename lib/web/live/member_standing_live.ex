defmodule Web.MemberStandingLive do
  use Web, :live_view_app_layout

  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Operation.AddAwayPeriod
  alias App.Operation.DeleteAwayPeriod
  alias App.Operation.EndAwayPeriod
  alias App.Repo
  alias Web.Components.NotAPersonSwitch
  alias Web.Components.Standing

  # A member's standing (#366): Active, away for a dated period, or not a person. SAR
  # Duty's own data, never sent to D4H, and members don't see it.
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = socket.assigns.current_team |> Member.find!(params["id"]) |> Repo.preload(:team)

    {:noreply,
     socket
     |> assign(:page_title, "#{member.name} · Standing")
     |> assign(:member, member)
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
    end
  end

  def handle_event("end-away", %{"id" => id}, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case EndAwayPeriod.call(team, id, user) do
      {:ok, _period} ->
        {:noreply, socket |> put_flash(:info, "Away period ended.") |> load_standing()}

      :error ->
        {:noreply, put_flash(socket, :error, "Only a current away period can end early.")}
    end
  end

  def handle_event("delete-away", %{"id" => id}, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    {:ok, _period} = DeleteAwayPeriod.call(team, id, user)
    {:noreply, socket |> put_flash(:info, "Away period deleted.") |> load_standing()}
  end

  def handle_info({:not_a_person_changed, not_a_person}, socket) do
    member = %{socket.assigns.member | not_a_person: not_a_person}
    {:noreply, socket |> assign(:member, member) |> load_standing()}
  end

  defp load_standing(socket) do
    member = socket.assigns.member
    today = Service.Period.today(DateTime.utc_now(), member.team.timezone)
    periods = MemberAwayPeriod.for_member(member)

    assign(socket,
      today: today,
      periods: periods,
      standing: MemberAwayPeriod.standing(member, periods, today)
    )
  end

  defp assign_new_form(socket) do
    changeset =
      MemberAwayPeriod.build_changeset(%MemberAwayPeriod{starts_on: socket.assigns.today})

    assign(socket, :away_form, to_form(changeset, as: "away"))
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Members" path={~p"/teams/#{@current_team}/members/"} />
      <:item label={@member.name} />
    </.breadcrumbs>

    <h1 class="title">{@member.name}</h1>
    <.member_tabs member={@member} active_tab={:standing} />
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content
          member={@member}
          maps_app={@current_user.maps_app}
          standing={@standing}
        />
      </aside>
      <main class="content-2/3">
        <section id="standing">
          <h2 class="heading">Standing</h2>
          <p id="standing-now" class="lead">{Standing.text(@standing)}</p>
          <p class="hint">
            Active unless the member is away or not a person. SAR Duty keeps it, and
            nothing here goes to D4H. Members do not see it.
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
              {MemberAwayPeriod.reason_label(period.reason)}
              <div :if={period.note} class="text-text-muted">{period.note}</div>
            </:col>
            <:col :let={period} label="First day" class="w-px whitespace-nowrap">
              {Service.Format.day(period.starts_on)}
            </:col>
            <:col :let={period} label="Last day" class="w-px whitespace-nowrap">
              {Service.Format.day(period.ends_on)}
            </:col>
            <:col :let={period} label="" class="w-px whitespace-nowrap">
              <.button
                :if={MemberAwayPeriod.early_end(period, @today) != :error}
                id={"end-away-#{period.id}"}
                size={:sm}
                phx-click="end-away"
                phx-value-id={period.id}
                data-confirm={"End this away period today? #{@member.name} is active from today."}
              >
                End today
              </.button>
              <.button
                id={"delete-away-#{period.id}"}
                size={:sm}
                variant={:danger}
                phx-click="delete-away"
                phx-value-id={period.id}
                data-confirm={"Delete this away period? It comes out of #{@member.name}'s standing. The history keeps a record."}
              >
                Delete
              </.button>
            </:col>
          </.table>
          <p :if={@periods == []} id="no-away-periods" class="text-text-muted">
            No away periods.
          </p>

          <.form
            for={@away_form}
            id="away-form"
            phx-change="validate-away"
            phx-submit="add-away"
            class="max-w-xl mt-6"
          >
            <h3 class="subheading">Add an away period</h3>
            <.error_summary form={@away_form} />
            <div class="grid md:grid-cols-2 gap-x-6">
              <.input field={@away_form[:starts_on]} type="date" label="First day" />
              <.input field={@away_form[:ends_on]} type="date" label="Last day" />
            </div>
            <.input
              field={@away_form[:reason]}
              type="select"
              label="Reason"
              prompt="Select a reason"
              options={MemberAwayPeriod.reasons()}
            />
            <.input field={@away_form[:note]} type="textarea" label="Note (optional)" />
            <.form_actions>
              <.button variant={:success}>Add away period</.button>
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
end
