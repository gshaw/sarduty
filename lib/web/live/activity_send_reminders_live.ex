defmodule Web.ActivitySendRemindersLive do
  use Web, :live_view_app_layout

  import Web.Components.EmailPreview

  alias App.Mailer.ActivityMailer
  alias App.Model.Activity
  alias App.Model.Reminder
  alias App.Model.Standing
  alias App.Operation.SendReminders
  alias App.Validate.Message
  alias App.ViewData.ActivityMembers
  alias Service.Format

  # Send reminders (#608): who gets a reminder email, when each was emailed before, and
  # why everyone else on the activity gets none, then the email itself and one send.
  # Every row starts checked; unchecking a member leaves them out. SendReminders.plan/2
  # decides, and the preview is ActivityMailer's own HTML, with the team admin's message
  # as they type it (#609). Only before the start, on an activity that isn't deleted.
  def mount(%{"id" => id}, _session, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    activity = Web.ActivityLive.fetch_activity(team, id)
    now = DateTime.utc_now()

    if activity.deleted_at || not DateTime.before?(now, activity.started_at) do
      {:ok, leave(socket, activity)}
    else
      plan =
        activity
        |> ActivityMembers.load()
        |> SendReminders.plan(Reminder.for_activity(activity), Standing.retiring_ids(team))

      sender = SendReminders.sender(team, user, now)

      {:ok,
       assign(socket,
         page_title: "Send reminders",
         activity: activity,
         plan: plan,
         selected: MapSet.new(plan.send, & &1.member.id),
         sender: sender,
         message: "",
         preview: ActivityMailer.reminder_preview(activity, team, sender, nil)
       )}
    end
  end

  # A stale visitor goes back to the activity, as Add members sends them.
  defp leave(socket, %Activity{deleted_at: %DateTime{}} = activity),
    do: Web.ActivityLive.leave_deleted(socket, activity)

  defp leave(socket, activity) do
    socket
    |> put_flash(:error, SendReminders.error_text(:started))
    |> push_navigate(to: activity_path(socket, activity))
  end

  def handle_event("change", params, socket) do
    %{current_team: team, activity: activity, sender: sender} = socket.assigns
    message = Map.get(params, "message", "")

    {:noreply,
     assign(socket,
       selected: params |> selected_ids() |> MapSet.new(),
       message: message,
       preview:
         ActivityMailer.reminder_preview(activity, team, sender, Message.normalize(message))
     )}
  end

  # The batch note on the activity says what went, so there's no flash.
  def handle_event("send", params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns

    ids = selected_ids(params)
    message = Map.get(params, "message")

    case SendReminders.call(team, activity, user, ids, message, DateTime.utc_now()) do
      {:ok, _reminders} ->
        {:noreply, push_navigate(socket, to: activity_path(socket, activity))}

      {:error, reason} when reason in [:none_selected, :message_too_long] ->
        {:noreply, put_flash(socket, :error, SendReminders.error_text(reason))}

      {:error, :deleted} ->
        {:noreply, Web.ActivityLive.leave_deleted(socket, activity)}

      {:error, :started} ->
        {:noreply, leave(socket, activity)}
    end
  end

  # Swoosh's test adapter tells each process a reminder came from, this one included.
  def handle_info({:email, _email}, socket), do: {:noreply, socket}

  # Ids come from the browser; call/6 sends only to members its own plan has.
  defp selected_ids(params) do
    params
    |> Map.get("member_ids", [])
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {id, ""} -> [id]
        _other -> []
      end
    end)
  end

  defp activity_path(socket, activity),
    do: ~p"/teams/#{socket.assigns.current_team}/activities/#{activity.id}"

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item label={@activity.ref_id} path={~p"/teams/#{@current_team}/activities/#{@activity.id}"} />
      <:item label="Send reminders" />
    </.breadcrumbs>
    <h1 class="title">Send reminders</h1>
    <p class="lead">
      {@activity.title} · {Format.datetime_medium(@activity.started_at, @current_team.timezone)}
    </p>

    <.form for={%{}} id="email-form" phx-change="change" phx-submit="send">
      <section id="email-to">
        <h2 class="subheading">Who gets it</h2>
        <p class="hint mb-3">Members with no reply. Uncheck anyone you emailed recently.</p>
        <p :if={@plan.send == []} id="email-nobody">Nobody to email now.</p>
        <.table
          :if={@plan.send != []}
          id="email-to-table"
          rows={@plan.send}
          row_id={&"email-to-#{&1.member.id}"}
          class="table-striped w-fit"
        >
          <:col :let={email} label="" class="w-px" select_all>
            <input
              type="checkbox"
              id={"email-select-#{email.member.id}"}
              name="member_ids[]"
              value={email.member.id}
              checked={MapSet.member?(@selected, email.member.id)}
            />
          </:col>
          <:col :let={email} label="Name" class="whitespace-nowrap">
            <label for={"email-select-#{email.member.id}"}>{email.member.name}</label>
          </:col>
          <:col :let={email} label="Emailed before">
            {emailed_text(email.emailed, @current_team.timezone)}
          </:col>
        </.table>
      </section>

      <.left_out plan={@plan} service={@service} />

      <section id="email-preview-section" class="mt-8">
        <h2 class="subheading">What they get</h2>
        <p class="hint mb-3">
          From {@current_team.name}. Replies come to you at {@sender.email}.
        </p>
        <div class="measure">
          <.input
            id="email-message"
            name="message"
            type="textarea"
            label="Message (optional)"
            value={@message}
            rows="4"
            maxlength={Message.max_length()}
            phx-debounce="300"
          >
            Your own words, under the date and place. Up to {Message.limit_text()}.
            Members who replied don't get this. To tell everyone on the activity something, <.a
              id="reminders-update-link"
              navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}/updates"}
            >send an update</.a>.
          </.input>
        </div>
        <.email_preview subject={@preview.subject} html={@preview.html} />
      </section>

      <.form_actions class="mt-8">
        <.button
          :if={@plan.send != []}
          id="email-send"
          variant={:primary}
          disabled={MapSet.size(@selected) == 0}
          phx-disable-with="Sending…"
        >
          {Format.count(MapSet.size(@selected), one: "Send 1 email", many: "Send %d emails")}
        </.button>
        <.button id="email-cancel" navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}"}>
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

  # "Oct 22 and Oct 24", or empty for a member never emailed.
  defp emailed_text([], _timezone), do: nil

  defp emailed_text(emailed, timezone),
    do: emailed |> Enum.map(&Format.month_day(&1.sent_at, timezone)) |> Format.and_list()

  attr :plan, :map, required: true
  attr :service, :string, required: true

  # Everyone else on the activity, a line per reason: a count of who replied, and the
  # names of members with no reply who get nothing.
  defp left_out(assigns) do
    assigns =
      assign(assigns,
        replied: assigns.plan.replied,
        reasons: Enum.group_by(assigns.plan.left_out, &elem(&1, 1), &elem(&1, 0))
      )

    ~H"""
    <section
      :if={@replied != [] or @reasons != %{}}
      id="email-left-out"
      class="mt-8"
    >
      <h2 class="subheading">Who doesn't get it</h2>
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
