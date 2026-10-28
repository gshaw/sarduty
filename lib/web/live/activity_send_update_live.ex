defmodule Web.ActivitySendUpdateLive do
  use Web, :live_view_app_layout

  import Web.Components.EmailPreview

  alias App.Mailer.ActivityMailer
  alias App.Model.Activity
  alias App.Model.ActivityUpdate
  alias App.Operation.SendActivityUpdate
  alias App.Operation.SendReminders
  alias App.Validate.Message
  alias App.ViewData.ActivityMembers
  alias Service.Format

  # Send an update (#609): the team admin's own message to the members on an activity,
  # whatever their reply. Every member with an email starts checked, a table per reply,
  # each with select all. Each email ends with where the member stands, so the preview
  # shows one ending at a time. Earlier updates are listed first, so nobody sends the
  # same one twice. Only before the start, on an activity that isn't deleted.
  def mount(%{"id" => id}, _session, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    activity = Web.ActivityLive.fetch_activity(team, id)
    now = DateTime.utc_now()

    if Activity.open?(activity, now) do
      {:ok,
       socket
       |> assign(
         page_title: "Send an update",
         activity: activity,
         sent_before: sent_before(team, activity, now),
         sender: SendReminders.sender(team, user, now),
         message: ""
       )
       |> assign_plan()
       |> assign_preview()}
    else
      {:ok, leave(socket, activity)}
    end
  end

  # Everyone starts checked, and the preview shows the first ending.
  defp assign_plan(socket) do
    plan = socket.assigns.activity |> ActivityMembers.load() |> SendActivityUpdate.plan()
    endings = endings(plan)

    assign(socket,
      plan: plan,
      endings: endings,
      selected: plan.groups |> Enum.flat_map(&elem(&1, 1)) |> MapSet.new(& &1.member.id),
      ending: List.first(endings, :signed_up)
    )
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
  defp endings(plan) do
    for {status, rows} <- plan.groups,
        row <- rows,
        uniq: true,
        do: ActivityMailer.update_ending(status, row.member)
  end

  defp assign_preview(socket) do
    %{activity: activity, current_team: team, sender: sender} = socket.assigns
    message = Message.normalize(socket.assigns.message)

    assign(
      socket,
      :preview,
      ActivityMailer.update_preview(activity, team, sender, message, socket.assigns.ending)
    )
  end

  # A stale visitor goes back to the activity, as Add members sends them.
  defp leave(socket, %Activity{deleted_at: %DateTime{}} = activity),
    do: Web.ActivityLive.leave_deleted(socket, activity)

  defp leave(socket, activity) do
    socket
    |> put_flash(:error, SendActivityUpdate.error_text(:started))
    |> push_navigate(to: activity_path(socket, activity))
  end

  def handle_event("change", params, socket) do
    {:noreply,
     socket
     |> assign(
       selected: params |> selected_ids() |> MapSet.new(),
       message: Map.get(params, "message", ""),
       ending: ending(params["preview"], socket.assigns.endings, socket.assigns.ending)
     )
     |> assign_preview()}
  end

  # The batch shows on the page, so there's no flash.
  def handle_event("send", params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns
    ids = selected_ids(params)
    message = Map.get(params, "message")

    case SendActivityUpdate.call(team, activity, user, ids, message, DateTime.utc_now()) do
      {:ok, _updates} ->
        {:noreply, push_navigate(socket, to: activity_path(socket, activity))}

      {:error, reason} when reason in [:no_message, :message_too_long, :none_selected] ->
        {:noreply, put_flash(socket, :error, SendActivityUpdate.error_text(reason))}

      {:error, :deleted} ->
        {:noreply, Web.ActivityLive.leave_deleted(socket, activity)}

      {:error, :started} ->
        {:noreply, leave(socket, activity)}
    end
  end

  # Swoosh's test adapter tells each process an email came from, this one included.
  def handle_info({:email, _email}, socket), do: {:noreply, socket}

  # Only an ending the page offers; anything else from the browser keeps the one shown.
  defp ending(param, endings, current),
    do: Enum.find(endings, current, &(Atom.to_string(&1) == param))

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
      <:item label="Send an update" />
    </.breadcrumbs>
    <h1 class="title">Send an update</h1>
    <p class="lead">
      {@activity.title} · {Format.datetime_medium(@activity.started_at, @current_team.timezone)}
    </p>

    <section :if={@sent_before != []} id="update-sent-before" class="mb-8">
      <h2 class="subheading">Sent before</h2>
      <ul class="space-y-3">
        <li
          :for={batch <- @sent_before}
          id={"update-batch-#{DateTime.to_unix(batch.sent_at, :microsecond)}"}
        >
          <p class="hint">{batch_text(batch, @current_team.timezone)}</p>
          <p class="measure whitespace-pre-line">{batch.message}</p>
        </li>
      </ul>
    </section>

    <.form for={%{}} id="update-form" phx-change="change" phx-submit="send">
      <div class="measure">
        <.input
          id="update-message"
          name="message"
          type="textarea"
          label="Message"
          value={@message}
          rows="4"
          maxlength={Message.max_length()}
          phx-debounce="300"
        >
          Plain text, under the date and place. Up to {Message.limit_text()}.
        </.input>
      </div>

      <section id="update-to">
        <h2 class="subheading">Who gets it</h2>
        <p class="hint mb-3">
          Everyone on the activity with an email. Members with no reply get the reply buttons too.
          <span :if={no_reply?(@plan)} id="update-reminders-hint">
            To ask only them, <.a
              id="update-reminders-link"
              navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}/reminders"}
            >send reminders</.a>.
          </span>
        </p>
        <p :if={@plan.groups == []} id="update-nobody">Nobody on the activity has an email.</p>
        <div :for={{status, rows} <- @plan.groups} class="measure mb-6">
          <.table
            id={"update-to-#{status}"}
            rows={rows}
            row_id={&"update-to-#{&1.member.id}"}
            class="table-striped"
          >
            <:col :let={row} label="" class="w-px" select_all>
              <input
                type="checkbox"
                id={"update-select-#{row.member.id}"}
                name="member_ids[]"
                value={row.member.id}
                checked={MapSet.member?(@selected, row.member.id)}
              />
            </:col>
            <:col :let={row} label={status_title(status)} class="whitespace-nowrap">
              <label for={"update-select-#{row.member.id}"}>{row.member.name}</label>
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
        <h2 class="subheading">What they get</h2>
        <p class="hint mb-3">
          From {@current_team.name}. Replies come to you at {@sender.email}.
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
          :if={@plan.groups != []}
          id="update-send"
          variant={:primary}
          disabled={MapSet.size(@selected) == 0}
          phx-disable-with="Sending…"
          {send_confirm(
            MapSet.size(@selected),
            "Email #{members_text(MapSet.size(@selected))} about #{@activity.title}?",
            ["Each gets your message, whatever their reply."]
          )}
        >
          {Format.count(MapSet.size(@selected), one: "Send 1 email", many: "Send %d emails")}
        </.button>
        <.button id="update-cancel" navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}"}>
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

  defp members_text(count), do: Format.count(count, one: "%d member", many: "%d members")

  defp no_reply?(plan), do: Enum.any?(plan.groups, &(elem(&1, 0) == "requested"))

  defp status_title("attending"), do: "Signed up"
  defp status_title("absent"), do: "Can't make it"
  defp status_title("requested"), do: "No reply"

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
