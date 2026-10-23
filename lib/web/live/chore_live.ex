defmodule Web.ChoreLive do
  use Web, :live_view_app_layout

  import Web.ChoreText, only: [status_badge: 1]

  alias App.Model.Chore
  alias App.Operation.SaveChore
  alias Service.Format

  # One chore (#341), /teams/:subdomain/chores/:id: a team admin accepts it, changes it,
  # or declines it with a reason the member sees, in any status.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    if !team.member_logins, do: raise(Web.Status.NotFound)
    chore = Chore.find!(team, id)

    socket
    |> assign(page_title: chore.description, chore: chore)
    |> assign_decline_form(%{})
    |> then(&{:ok, &1})
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
        <.a navigate={~p"/teams/#{@current_team}/members/#{@chore.member_id}"}>
          {@chore.member.name}
        </.a>
      </dd>
      <dt>Date</dt>
      <dd>{Format.date_short(@chore.date)}</dd>
      <dt>Time</dt>
      <dd>{Format.duration(@chore.minutes)}</dd>
      <dt>Category</dt>
      <dd>{@chore.chore_category.title}</dd>
      <dt>Logged</dt>
      <dd>{Format.datetime_short(@chore.inserted_at, @current_team.timezone)}</dd>
      <dt>Status</dt>
      <dd id="chore-status">
        <.status_badge chore={@chore} />
        <span :if={@chore.status == :accepted}>Accepted</span>
        <span :if={@chore.decided_at} class="hint">
          {Format.datetime_short(@chore.decided_at, @current_team.timezone)}{if @chore.decided_by_user,
            do: ", #{@chore.decided_by_user.email}"}
        </span>
      </dd>
      <div :if={@chore.status == :declined}>
        <dt>Why not</dt>
        <dd id="chore-decline-reason">{@chore.decline_reason}</dd>
      </div>
    </dl>

    <.form_actions>
      <.button
        :if={@chore.status != :accepted}
        id="chore-accept"
        type="button"
        variant={:success}
        phx-click="accept"
      >
        Accept chore
      </.button>
      <.button id="chore-change" navigate={~p"/teams/#{@current_team}/chores/#{@chore.id}/edit"}>
        Change chore
      </.button>
    </.form_actions>

    <section :if={@chore.status != :declined} id="chore-decline" class="mt-8">
      <h2 class="subheading">Decline</h2>
      <.form for={@decline_form} id="decline-form" class="measure" phx-submit="decline">
        <.input field={@decline_form[:reason]} type="textarea" rows="3" label="Why not">
          {first_name(@chore.member.name)} sees this on their Chores page.
        </.input>
        <.form_actions>
          <.button id="chore-decline-button" variant={:danger}>Decline chore</.button>
        </.form_actions>
      </.form>
    </section>
    """
  end

  defp first_name(name), do: name |> String.split(" ", parts: 2) |> hd()

  def handle_event("accept", _params, socket) do
    %{current_team: team, current_user: user, chore: chore} = socket.assigns
    {:ok, _chore} = SaveChore.accept_one(team, chore, user, DateTime.utc_now())

    socket
    |> put_flash(:info, "Accepted #{chore.description}.")
    |> push_navigate(to: ~p"/teams/#{team}/chores")
    |> then(&{:noreply, &1})
  end

  def handle_event("decline", %{"decline" => %{"reason" => reason}}, socket) do
    %{current_team: team, current_user: user, chore: chore} = socket.assigns

    case SaveChore.decline(team, chore, reason, user, DateTime.utc_now()) do
      {:ok, _chore} ->
        socket
        |> put_flash(:info, "Declined #{chore.description}.")
        |> push_navigate(to: ~p"/teams/#{team}/chores")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        errors = for {:decline_reason, error} <- changeset.errors, do: {:reason, error}
        {:noreply, assign_decline_form(socket, %{"reason" => reason}, errors)}
    end
  end
end
