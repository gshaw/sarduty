defmodule Web.ChoreLive do
  use Web, :live_view_app_layout

  import Web.ChoreText, only: [own_box: 1, status_badge: 1]

  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.SaveChore
  alias App.Operation.SendChores
  alias Service.Format
  alias Web.ChoreText

  # One chore (#341), /teams/:subdomain/chores/:id: a team admin accepts it, changes it,
  # or declines it with a reason the member sees, in any status. Each sends its chore
  # category's activity for the month to D4H. A team admin accepts their own chore only
  # once they select the box that says they meant it (#697).
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    if !Team.chores?(team), do: raise(Web.Status.NotFound)
    chore = Chore.find!(team, id)

    socket
    |> assign(page_title: chore.description, chore: chore, own: false)
    |> assign(own_chore?: Chore.own?(chore, socket.assigns.current_member))
    |> assign(decided_by: decider_name(team, chore.decided_by_user, DateTime.utc_now()))
    |> assign(activity: chore.chore_event && ChoreEvent.local_activity(chore.chore_event))
    |> assign_decline_form(%{})
    |> then(&{:ok, &1})
  end

  # The team admin who decided, by their member name, or their email when no member has it.
  defp decider_name(_team, nil, _now), do: nil

  defp decider_name(team, user, now) do
    case Member.find_by_email(team, user.email, now) do
      %Member{name: name} -> name
      nil -> user.email
    end
  end

  defp assign_decline_form(socket, params, errors \\ []),
    do: assign(socket, :decline_form, to_form(params, as: "decline", errors: errors))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Chores" path={~p"/teams/#{@current_team}/chores"} />
      <:item label={@chore.description} />
    </.breadcrumbs>
    <h1 class="title">{@chore.description}</h1>

    <dl id="chore-details" class="mb-4">
      <dt>Member</dt>
      <dd>
        <.a navigate={~p"/teams/#{@current_team}/members/#{@chore.member_id}"}>{@chore.member.name}</.a>
      </dd>
      <dt>Date</dt>
      <dd>{Format.date_short(@chore.date)}</dd>
      <dt>Time</dt>
      <dd>{Format.duration(@chore.minutes)}</dd>
      <dt>Category</dt>
      <dd>{@chore.chore_category.title}</dd>
      <dt>Logged</dt>
      <dd>
        {Format.datetime_short(@chore.inserted_at, @current_team.timezone)}
      </dd>
      <dt>Status</dt>
      <dd id="chore-status">
        <.status_badge chore={@chore} />
        <span :if={@chore.status == :accepted}>Accepted</span>
        <span :if={@chore.decided_at} class="hint">
          {Format.datetime_short(@chore.decided_at, @current_team.timezone)}{if @decided_by,
            do: ", #{@decided_by}"}
        </span>
      </dd>
      <div :if={@chore.status == :declined}>
        <dt>Why not</dt>
        <dd id="chore-decline-reason">{@chore.decline_reason}</dd>
      </div>
      <div :if={@chore.chore_event}>
        <dt>Activity</dt>
        <dd id="chore-activity">
          <.a :if={@activity} navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}"}>{@activity.title}</.a>
          <span :if={!@activity and @chore.chore_event.d4h_activity_id} class="hint">
            Sent. Linked after the next refresh.
          </span>
          <span :if={!@chore.chore_event.d4h_activity_id} class="hint">
            Not sent yet
          </span>
          <span :if={@chore.chore_event.send_note} class="hint block">
            {@chore.chore_event.send_note}
          </span>
        </dd>
      </div>
    </dl>

    <.form for={%{}} id="accept-form" phx-change="own" phx-submit="accept">
      <.own_box :if={@own_chore? and @chore.status != :accepted} checked={@own} />
      <.form_actions>
        <.button
          :if={@chore.status != :accepted}
          id="chore-accept"
          variant={:success}
          disabled={@own_chore? and !@own}
          phx-disable-with="Sending…"
        >
          Accept chore
        </.button>
        <.button id="chore-change" navigate={~p"/teams/#{@current_team}/chores/#{@chore.id}/edit"}>
          Change chore
        </.button>
      </.form_actions>
    </.form>

    <section :if={@chore.status != :declined} id="chore-decline" class="mt-8">
      <h2 class="subheading">Decline</h2>
      <.form for={@decline_form} id="decline-form" class="measure" phx-submit="decline">
        <.input field={@decline_form[:reason]} type="textarea" rows="3" label="Why not">
          {Member.first_name(@chore.member)} sees this on their Chores page.
        </.input>
        <.form_actions>
          <.button
            id="chore-decline-button"
            variant={:danger}
            phx-disable-with="Sending…"
          >
            Decline chore
          </.button>
        </.form_actions>
      </.form>
    </section>
    """
  end

  def handle_event("own", params, socket),
    do: {:noreply, assign(socket, :own, params["own"] == "true")}

  def handle_event("accept", params, socket) do
    %{current_team: team, current_user: user, current_member: member, chore: chore} =
      socket.assigns

    opts = [member: member, own: params["own"] == "true"]

    case SaveChore.accept_one(team, chore, user, DateTime.utc_now(), opts) do
      {:ok, accepted} ->
        {:noreply, send_and_return(socket, accepted, "Accepted #{chore.description}")}

      {:error, :own} ->
        {:noreply, put_flash(socket, :error, ChoreText.own_refused())}
    end
  end

  def handle_event("decline", %{"decline" => %{"reason" => reason}}, socket) do
    %{current_team: team, current_user: user, chore: chore} = socket.assigns

    case SaveChore.decline(team, chore, reason, user, DateTime.utc_now()) do
      {:ok, declined} ->
        {:noreply, send_and_return(socket, declined, "Declined #{chore.description}")}

      {:error, changeset} ->
        errors = for {:decline_reason, error} <- changeset.errors, do: {:reason, error}
        {:noreply, assign_decline_form(socket, %{"reason" => reason}, errors)}
    end
  end

  @doc """
  Sends the team's chore events after a team admin's change, and goes back to the Chores
  page, which shows why a send did not go through, on the view `chore` is in now. `done`
  says what changed.
  """
  def send_and_return(socket, chore, done) do
    %{current_team: team, current_user: user} = socket.assigns
    result = SendChores.call(team, user, DateTime.utc_now())
    {kind, text} = ChoreText.send_flash(done, result)

    socket
    |> put_flash(kind, text)
    |> push_navigate(to: Web.ChoreCollectionLive.view_path(team, chore.status))
  end
end
