defmodule Web.ActivityMembersLive.Ask do
  @moduledoc """
  Ask for a reply (#895, #920), a step before the start: email “Will you be there?” to
  the checked members with no reply, once a team admin picks them on the Members tab. To
  the member it's an invitation reminder, so the email and the operation keep that name.
  It lists who gets one, with when each was emailed before, then everyone else checked
  who gets none, and why: they replied, are retiring, turned reminders off, or have no
  email (#608). Then the message (#609), starting with how many more are needed while
  short (#447), the email as it goes, and one send. SendReminders.plan/3 decides who gets
  one, and its call/6 checks again on send.
  """
  @behaviour Web.ActivityMembersLive.Action

  use Web, :live_component

  import Web.Components.Columns, only: [member_cell: 1]
  import Web.Components.EmailPreview
  import Web.Components.Table, only: [table: 1]

  alias App.Mailer.ActivityMailer
  alias App.Model.Activity
  alias App.Model.Reminder
  alias App.Model.Standing
  alias App.Operation.SendReminders
  alias App.Validate.Message
  alias App.ViewData.ActivityMembers
  alias Service.Format
  alias Web.ActivityMembersLive.Action

  @impl Action
  def value, do: "ask"

  @impl Action
  def label, do: "Ask for a reply"

  @impl Action
  def hint(_ctx, []), do: "Emails “Will you be there?” to the checked with no reply."

  # "Emails “Will you be there?” to the 2 checked with no reply. 1 has replied." The plan
  # leaves out the retiring, reminders off, and no email, and the step says who.
  def hint(%{retiring: retiring}, checked) do
    plan = SendReminders.plan(checked, [], retiring)
    send = length(plan.send)
    replied = length(plan.replied)
    left_out = length(plan.left_out)

    [
      send > 0 && "Emails “Will you be there?” to the #{send} checked with no reply.",
      left_out > 0 && "#{left_out} with no reply can't get one.",
      replied > 0 && "#{Action.count_verb(replied, "has", "have")} replied."
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  # Greyed when nobody checked has no reply (#920 G), or none of them can get one.
  @impl Action
  def unavailable(_ctx, []), do: nil

  def unavailable(%{retiring: retiring}, checked) do
    plan = SendReminders.plan(checked, [], retiring)

    cond do
      plan.send != [] -> nil
      plan.left_out == [] -> "Everyone checked has replied."
      true -> "Nobody checked with no reply can get one."
    end
  end

  @impl Action
  def offered?(%{activity: activity, now: now}), do: Activity.open?(activity, now)

  # The checked members with no reply that the plan emails: not retiring, reminders on,
  # and an email.
  @impl Action
  def count(%{retiring: retiring}, checked),
    do: checked |> SendReminders.plan([], retiring) |> Map.fetch!(:send) |> length()

  @impl Action
  def button_text(count),
    do: Format.count(count, one: "Ask 1 member", many: "Ask %d members")

  @impl Action
  def variant, do: :primary

  @impl Action
  def confirm(_ctx, _checked), do: %{}

  @impl Action
  def run(_checked), do: {:step, :ask}

  # The plan is the checked members as the step opened; later renders keep it.
  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    first? = !Map.has_key?(socket.assigns, :plan)
    socket = assign(socket, assigns)
    {:ok, if(first?, do: load(socket), else: socket)}
  end

  defp load(socket) do
    %{team: team, activity: activity, user: user, checked: checked, counts: counts} =
      socket.assigns

    now = DateTime.utc_now()

    socket
    |> assign(
      plan:
        SendReminders.plan(checked, Reminder.for_activity(activity), Standing.retiring_ids(team)),
      sender: SendReminders.sender(team, user, now)
    )
    |> assign_message(
      activity
      |> Activity.more_needed(counts, now)
      |> SendReminders.start_message()
    )
  end

  # The message as typed, and the preview with it.
  defp assign_message(socket, message) do
    %{team: team, activity: activity, sender: sender} = socket.assigns
    preview = ActivityMailer.reminder_preview(activity, team, sender, Message.normalize(message))
    assign(socket, message: message, preview: preview)
  end

  @impl Phoenix.LiveComponent
  def handle_event("change", params, socket),
    do: {:noreply, assign_message(socket, Map.get(params, "message", ""))}

  # The ids are the plan's, never the browser's; call/6 plans again and sends only to
  # members it still has, on the activity as it is now, which may have started.
  def handle_event("send", params, socket) do
    %{team: team, user: user, plan: plan} = socket.assigns
    activity = Web.ActivityLive.fetch_activity(team, socket.assigns.activity.id)
    message = Map.get(params, "message", "")
    ids = Enum.map(plan.send, & &1.member.id)

    outcome =
      team
      |> SendReminders.call(activity, user, ids, message, DateTime.utc_now())
      |> outcome()

    send(self(), outcome)
    {:noreply, assign_message(socket, message)}
  end

  # The tab with a toast, or the step again with the error for a message too long.
  defp outcome({:ok, []}), do: {:step_done, :error, "Nobody was emailed."}

  defp outcome({:ok, reminders}),
    do:
      {:step_done, :info,
       reminders
       |> length()
       |> Format.count(one: "Asking 1 member.", many: "Asking %d members.")}

  defp outcome({:error, :message_too_long}),
    do: {:step_flash, :error, SendReminders.error_text(:message_too_long)}

  defp outcome({:error, reason}), do: {:step_done, :error, SendReminders.error_text(reason)}

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign(assigns, count: length(assigns.plan.send))

    ~H"""
    <div id="ask-step">
      <.form for={%{}} id="ask-form" phx-change="change" phx-submit="send" phx-target={@myself}>
        <section id="ask-who">
          <h2 class="subheading">Who gets it</h2>
          <p :if={@plan.send == []} id="ask-nobody">Nobody to email now.</p>
          <.table
            :if={@plan.send != []}
            id="ask-to"
            rows={@plan.send}
            row_id={&"ask-to-#{&1.member.id}"}
            class="table-striped w-fit"
          >
            <:col :let={email} label="Member">
              <.member_cell
                member={email.member}
                team={@team}
                standing={@standings[email.member.id]}
              />
            </:col>
            <:col :let={email} label="Emailed before">
              {emailed_text(email.emailed, @team.timezone)}
            </:col>
          </.table>
        </section>

        <.left_out plan={@plan} service={@service} />

        <section id="ask-preview-section" class="mt-8">
          <div class="measure">
            <.input
              id="ask-message"
              name="message"
              type="textarea"
              label="Message (optional)"
              value={@message}
              rows="4"
              maxlength={Message.max_length()}
              phx-debounce="300"
            >
              Your own words, under the date and place. Up to {Message.limit_text()}.
            </.input>
          </div>
          <h2 class="subheading">What they get</h2>
          <p class="hint mb-3">
            From {@team.name}. Replies come to you at {@sender.email}.
          </p>
          <.email_preview subject={@preview.subject} html={@preview.html} />
        </section>

        <.form_actions class="mt-8">
          <.button
            :if={@count > 0}
            id="ask-send"
            variant={:primary}
            phx-disable-with="Sending…"
            {send_confirm(
              @count,
              "Email #{members_text(@count)} about #{@activity.title}?",
              ["Each gets “Will you be there?” and the reply buttons."]
            )}
          >
            {Format.count(@count, one: "Send 1 email", many: "Send %d emails")}
          </.button>
          <.button id="ask-cancel" patch={@back}>Cancel</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  defp members_text(count), do: Format.count(count, one: "%d member", many: "%d members")

  # "Oct 22 and Oct 24", or empty for a member never emailed.
  defp emailed_text([], _timezone), do: nil

  defp emailed_text(emailed, timezone),
    do: emailed |> Enum.map(&Format.month_day(&1.sent_at, timezone)) |> Format.and_list()

  attr :plan, :map, required: true
  attr :service, :string, required: true

  # Everyone else checked, a line per reason: a count of who replied, and the names of
  # members with no reply who get nothing.
  defp left_out(assigns) do
    assigns =
      assign(assigns,
        replied: assigns.plan.replied,
        reasons: Enum.group_by(assigns.plan.left_out, &elem(&1, 1), &elem(&1, 0))
      )

    ~H"""
    <section :if={@replied != [] or @reasons != %{}} id="ask-left-out" class="mt-8">
      <h2 class="subheading">Who does not get it</h2>
      <ul class="list-disc pl-6 space-y-1">
        <li :if={@replied != []} id="left-out-replied">
          Replied already, so no email: {replied_text(@replied)}.
        </li>
        <li
          :for={reason <- [:retiring, :reminders_off, :no_email]}
          :if={@reasons[reason]}
          id={"left-out-#{reason}"}
        >
          {reason_text(reason, @service)}: {names(@reasons[reason])}.
        </li>
      </ul>
    </section>
    """
  end

  defp replied_text(replied) do
    counts = ActivityMembers.counts(replied)

    [
      counts.attending > 0 &&
        Format.count(counts.attending, one: "%d signed up", many: "%d signed up"),
      counts.absent > 0 &&
        Format.count(counts.absent, one: "%d can't make it", many: "%d can't make it")
    ]
    |> Enum.filter(& &1)
    |> Format.and_list()
  end

  defp reason_text(:retiring, _service), do: "Retiring"
  defp reason_text(:reminders_off, _service), do: "Turned off invitation reminders"
  defp reason_text(:no_email, service), do: "No email in #{service}"

  defp names(members), do: members |> Enum.map(& &1.name) |> Format.and_list()
end
