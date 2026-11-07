defmodule Web.ActivityMembersLive.Update do
  @moduledoc """
  Send an update (#895), a step before and after the start (#896): the team admin's own
  message to the checked members, whatever their reply (#609). Who gets it is listed
  without tick boxes: they were picked on the Members tab. Before the start each email
  ends with where the member stands, so who gets it is a table per reply and the
  preview shows one ending at a time. From the start every email is the same, the
  message and Open activity, so it is one table and one preview. Earlier updates are
  listed first, so nobody sends the same one twice. SendActivityUpdate.plan/1 decides
  who gets one, and its call/6 checks again on send.
  """
  @behaviour Web.ActivityMembersLive.Action

  use Web, :live_component

  import Web.Components.Columns, only: [member_cell: 1]
  import Web.Components.EmailPreview
  import Web.Components.Table, only: [table: 1]

  alias App.Mailer.ActivityMailer
  alias App.Model.Activity
  alias App.Model.ActivityUpdate
  alias App.Operation.SendActivityUpdate
  alias App.Operation.SendReminders
  alias App.Validate.Message
  alias Service.Format
  alias Web.ActivityMembersLive.Action
  alias Web.Components.Reply

  @impl Action
  def value, do: "update"

  @impl Action
  def label, do: "Send an update"

  @impl Action
  # Before the start each email ends with where the member stands; from it, a link to the
  # activity, as the step's confirm says.
  def hint(%{activity: activity, now: now}, checked) do
    what =
      if Activity.started?(activity, now),
        do: "your message and a link to the activity.",
        else: "your message and where they stand."

    count = length(checked)
    reached = checked |> SendActivityUpdate.plan() |> reached()

    cond do
      checked == [] ->
        "The checked get #{what}"

      reached == count ->
        "#{Action.all_checked(count)} #{if count == 1, do: "gets", else: "get"} #{what}"

      true ->
        "#{reached} of the #{count} checked #{if reached == 1, do: "gets", else: "get"} #{what} #{Action.count_verb(count - reached, "has", "have")} no email."
    end
  end

  @impl Action
  def unavailable(_ctx, []), do: nil

  def unavailable(_ctx, checked),
    do:
      if(checked |> SendActivityUpdate.plan() |> reached() == 0,
        do: "Nobody checked has an email."
      )

  # It changes nothing on the activity, so only a deleted one stops it.
  @impl Action
  def offered?(%{activity: activity}), do: !Activity.deleted?(activity)

  # The checked members with an email.
  @impl Action
  def count(_ctx, checked), do: checked |> SendActivityUpdate.plan() |> reached()

  @impl Action
  def button_text(count), do: Format.count(count, one: "Email 1 member", many: "Email %d members")

  @impl Action
  def variant, do: :primary

  @impl Action
  def confirm(_ctx, _checked), do: %{}

  @impl Action
  def run(_checked), do: {:step, :update}

  defp reached(plan), do: Enum.sum_by(plan.groups, fn {_status, rows} -> length(rows) end)

  # The plan is the checked members as the step opened; later renders keep it.
  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    first? = !Map.has_key?(socket.assigns, :plan)
    socket = assign(socket, assigns)
    {:ok, if(first?, do: load(socket), else: socket)}
  end

  defp load(socket) do
    %{team: team, activity: activity, user: user, checked: checked} = socket.assigns
    now = DateTime.utc_now()
    plan = SendActivityUpdate.plan(checked)
    started? = Activity.started?(activity, now)
    endings = endings(plan, started?)

    socket
    |> assign(
      plan: plan,
      started?: started?,
      endings: endings,
      ending: List.first(endings, :signed_up),
      sent_before: sent_before(team, activity, now),
      sender: SendReminders.sender(team, user, now),
      message: "",
      message_error: nil
    )
    |> assign_preview()
  end

  # Each earlier send, with its sender's name on the team.
  defp sent_before(team, activity, now) do
    activity
    |> ActivityUpdate.for_activity()
    |> SendActivityUpdate.sent_before()
    |> Enum.map(&Map.put(&1, :sender, sender_name(team, &1.sent_by_user, now)))
  end

  defp sender_name(_team, nil, _now), do: nil

  defp sender_name(team, user, now) do
    sender = SendReminders.sender(team, user, now)
    sender.name || sender.email
  end

  # The endings the plan's members get, in its order, for the preview's choices.
  defp endings(plan, started?) do
    for {status, rows} <- plan.groups,
        row <- rows,
        uniq: true,
        do: SendActivityUpdate.ending(status, row.member, started?)
  end

  # After the start everyone gets the same email, so one table, by name.
  defp everyone(plan) do
    plan.groups
    |> Enum.flat_map(fn {_status, rows} -> rows end)
    |> Enum.sort_by(&String.downcase(&1.member.name))
  end

  defp assign_preview(socket) do
    %{activity: activity, team: team, sender: sender, message: message, ending: ending} =
      socket.assigns

    preview =
      ActivityMailer.update_preview(activity, team, sender, Message.normalize(message), ending)

    assign(socket, preview: preview)
  end

  # The message box keeps its error until the team admin types in it.
  @impl Phoenix.LiveComponent
  def handle_event("change", params, socket) do
    %{endings: endings, ending: ending, message: message, message_error: message_error} =
      socket.assigns

    new_message = Map.get(params, "message", message)

    {:noreply,
     socket
     |> assign(
       message: new_message,
       message_error: if(new_message == message, do: message_error),
       ending: pick_ending(params["preview"], endings, ending)
     )
     |> assign_preview()}
  end

  # The ids are the plan's, never the browser's; call/6 plans again and sends only to
  # members it still has, on the activity as it is now, which may have started.
  def handle_event("send", params, socket) do
    %{team: team, user: user, plan: plan} = socket.assigns
    activity = Web.ActivityLive.fetch_activity(team, socket.assigns.activity.id)
    message = Map.get(params, "message", "")
    ids = for {_status, rows} <- plan.groups, row <- rows, do: row.member.id

    outcome =
      team
      |> SendActivityUpdate.call(activity, user, ids, message, DateTime.utc_now())
      |> outcome()

    send(self(), outcome)

    {:noreply,
     socket |> assign(message: message, message_error: message_error(outcome)) |> assign_preview()}
  end

  # The tab with a toast, or the step again with the toast and the error on the message
  # box.
  defp outcome({:ok, []}), do: {:step_done, :error, "Nobody was emailed."}

  defp outcome({:ok, updates}),
    do:
      {:step_done, :info,
       updates |> length() |> Format.count(one: "Sending 1 update.", many: "Sending %d updates.")}

  defp outcome({:error, reason}) when reason in [:no_message, :message_too_long],
    do: {:step_flash, :error, SendActivityUpdate.error_text(reason)}

  defp outcome({:error, reason}),
    do: {:step_done, :error, SendActivityUpdate.error_text(reason)}

  defp message_error({:step_flash, :error, text}), do: text
  defp message_error(_outcome), do: nil

  # Only an ending the step offers; anything else from the browser keeps the one shown.
  defp pick_ending(param, endings, current),
    do: Enum.find(endings, current, &(Atom.to_string(&1) == param))

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign(assigns, count: reached(assigns.plan))

    ~H"""
    <div id="update-step">
      <section :if={@sent_before != []} id="update-sent-before" class="mb-8">
        <h2 class="subheading">Sent before</h2>
        <ul class="space-y-3">
          <li
            :for={batch <- @sent_before}
            id={"update-batch-#{DateTime.to_unix(batch.sent_at, :microsecond)}"}
          >
            <p class="hint">{batch_text(batch, @team.timezone)}</p>
            <p class="measure whitespace-pre-line">{batch.message}</p>
          </li>
        </ul>
      </section>

      <.form for={%{}} id="update-form" phx-change="change" phx-submit="send" phx-target={@myself}>
        <section id="update-who">
          <h2 class="subheading">Who gets it</h2>
          <p :if={@plan.groups == []} id="update-nobody">Nobody checked has an email.</p>
          <div :if={@started? and @plan.groups != []} class="measure mb-6">
            <.table
              id="update-to-members"
              rows={everyone(@plan)}
              row_id={&"update-to-#{&1.member.id}"}
              class="table-striped"
            >
              <:col :let={row} label="Member">
                <.member_cell
                  member={row.member}
                  team={@team}
                  standing={@standings[row.member.id]}
                />
              </:col>
            </.table>
          </div>
          <div :for={{status, rows} <- @plan.groups} :if={!@started?} class="measure mb-6">
            <.table
              id={"update-to-#{status}"}
              rows={rows}
              row_id={&"update-to-#{&1.member.id}"}
              class="table-striped"
            >
              <:col :let={row} label={Reply.status_text(status, false)}>
                <.member_cell
                  member={row.member}
                  team={@team}
                  standing={@standings[row.member.id]}
                />
              </:col>
              <:col :let={row} label="">
                <span :if={ActivityMailer.update_ending(status, row.member) == :open} class="hint">
                  Turned off reminders, so no reply buttons
                </span>
              </:col>
            </.table>
          </div>
          <p :if={@plan.no_email != []} id="update-no-email">
            No email in {@service}, so no update: {names(@plan.no_email)}.
          </p>
        </section>

        <section :if={@endings != []} id="update-preview-section" class="mt-8">
          <div class="measure">
            <.input
              id="update-message"
              name="message"
              type="textarea"
              label="Message"
              value={@message}
              errors={List.wrap(@message_error)}
              rows="4"
              maxlength={Message.max_length()}
              phx-debounce="300"
            >
              Plain text, under the date and place. Up to {Message.limit_text()}.
            </.input>
          </div>
          <h2 class="subheading">What they get</h2>
          <p class="hint mb-3">
            From {@team.name}. Replies come to you at {@sender.email}.
          </p>
          <fieldset :if={length(@endings) > 1} id="update-preview-for" class="mb-4">
            <legend class="label">Show the email for</legend>
            <label :for={ending <- @endings} class="choice">
              <input
                type="radio"
                id={"update-preview-#{ending}"}
                name="preview"
                value={ending}
                checked={ending == @ending}
              />
              {ending_title(ending)}
            </label>
          </fieldset>
          <.email_preview subject={@preview.subject} html={@preview.html} />
        </section>

        <.form_actions class="mt-8">
          <.button
            :if={@count > 0}
            id="update-send"
            variant={:primary}
            phx-disable-with="Sending…"
            data-confirm-needs="#update-message"
            {send_confirm(
              @count,
              "Email #{members_text(@count)} about #{@activity.title}?",
              [confirm_text(@started?)]
            )}
          >
            {Format.count(@count, one: "Send 1 email", many: "Send %d emails")}
          </.button>
          <.button id="update-back" patch={@back}>Back</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  defp members_text(count), do: Format.count(count, one: "%d member", many: "%d members")

  defp confirm_text(true = _started?), do: "Each gets your message and a link to the activity."
  defp confirm_text(false), do: "Each gets your message, whatever their reply."

  # Only before the start: from it there is one ending, so no choice.
  defp ending_title(:signed_up), do: "Signed up"
  defp ending_title(:cant_make_it), do: "Can't make it"
  defp ending_title(:ask), do: "No reply"
  defp ending_title(:open), do: "No reply, reminders off"

  # "Oct 26, 18:02 by Alex Chen to 7 members", with any that failed.
  defp batch_text(batch, timezone) do
    [
      Format.month_day_time(batch.sent_at, timezone),
      batch.sender && "by #{batch.sender}",
      "to " <> Format.count(batch.members, one: "%d member", many: "%d members")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
    |> Kernel.<>(failed_text(batch.failed))
  end

  defp failed_text(0), do: ""
  defp failed_text(failed), do: ", " <> Format.count(failed, one: "%d failed", many: "%d failed")

  defp names(members), do: members |> Enum.map(& &1.name) |> Format.and_list()
end
