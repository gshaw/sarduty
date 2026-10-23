defmodule Web.MeChoresLive do
  use Web, {:live_view_app_layout, access: :member}

  import Web.ChoreText, only: [status_badge: 1]
  import Web.Components.Chart, only: [stat: 1]

  alias App.Model.Chore
  alias App.Operation.SaveChore
  alias App.ViewData.MemberChores
  alias Service.Format
  alias Web.ChoreText

  # A member's chores (#341), /teams/:subdomain/me/chores: every chore by the month it was
  # done, with what a team admin decided. A member changes a chore only while it waits.
  def mount(_params, _session, socket) do
    member = socket.assigns.current_member
    today = Service.Period.today(DateTime.utc_now(), member.team.timezone)

    socket
    |> assign(page_title: "Chores", member: member, today: today)
    |> assign_chores()
    |> then(&{:ok, &1})
  end

  defp assign_chores(socket) do
    chores = Chore.get_all_for_member(socket.assigns.member)

    assign(socket,
      months: MemberChores.months(chores),
      stats: MemberChores.stats(chores, socket.assigns.today.year)
    )
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@member.team}/me"} />
      <:item label="Chores" />
    </.breadcrumbs>
    <div class="heading-row">
      <h1 class="title">Chores</h1>
      <.button
        id="chore-log"
        variant={:success}
        navigate={~p"/teams/#{@member.team}/me/chores/new"}
      >
        Log a chore
      </.button>
    </div>
    <p class="lead measure">
      Time you give the team outside activities, such as fixing equipment or admin. A team admin accepts each chore before it counts.
    </p>

    <.empty_state :if={@months == []} id="no-chores" title="No chores yet">
      Log a chore after you do one. It counts once a team admin accepts it.
    </.empty_state>

    <div :if={@months != []} id="chore-stats" class="chart-stats">
      <.stat
        id="stat-accepted-hours"
        value={Format.duration(@stats.accepted_minutes)}
        label={"Accepted in #{@today.year}"}
      />
      <.stat
        id="stat-accepted-count"
        value={Format.number(@stats.accepted_count)}
        label={"Chores accepted in #{@today.year}"}
      />
      <.stat
        id="stat-waiting"
        value={Format.duration(@stats.waiting_minutes)}
        label="Waiting for a team admin"
      />
    </div>

    <section :for={month <- @months} id={"chores-#{Date.to_iso8601(month.month)}"} class="mt-8">
      <div class="heading-row">
        <h2 class="subheading">{Format.month_year_long(month.month)}</h2>
        <span class="hint">{ChoreText.summary(month)}</span>
      </div>
      <.table
        id={"chores-table-#{Date.to_iso8601(month.month)}"}
        rows={month.chores}
        row_id={&"chore-#{&1.id}"}
        class="table-striped table-stack"
      >
        <:col :let={chore} label="Date" class="w-1/12 whitespace-nowrap">
          {Format.day_in_year(chore.date, @today)}
        </:col>
        <:col :let={chore} label="What you did" class="stack-title">
          {chore.description}
          <span class="hint block">{chore.chore_category.title}</span>
          <span :if={chore.status == :declined} class="hint block mt-1">
            {ChoreText.declined(chore, @member.team.timezone)}
          </span>
        </:col>
        <:col :let={chore} label="Time" class="w-1/12 whitespace-nowrap" align="right">
          {Format.duration(chore.minutes)}
        </:col>
        <:col :let={chore} label="" class="stack-optional w-px whitespace-nowrap">
          <.status_badge chore={chore} />
          <.a
            :if={Chore.member_can_change?(chore)}
            id={"chore-change-#{chore.id}"}
            navigate={~p"/teams/#{@member.team}/me/chores/#{chore.id}/edit"}
          >
            Change
          </.a>
          <.a
            :if={chore.status == :declined}
            id={"chore-delete-#{chore.id}"}
            href="#"
            phx-click="delete"
            phx-value-id={chore.id}
            data-confirm={"Delete #{chore.description}?"}
          >
            Delete
          </.a>
        </:col>
      </.table>
    </section>

    <p :if={@months != []} class="hint mt-4">To change an accepted chore, ask a team admin.</p>
    """
  end

  def handle_event("delete", %{"id" => id}, socket) do
    member = socket.assigns.member
    chore = Chore.find_for_member!(member, id)

    socket =
      case SaveChore.delete_own(member, chore) do
        :ok ->
          put_flash(socket, :info, "Deleted #{chore.description}.")

        {:error, :decided} ->
          put_flash(socket, :error, "This chore cannot be deleted. A team admin has accepted it.")
      end

    {:noreply, assign_chores(socket)}
  end
end
