defmodule Web.ActivityMembersLive.RemoveBeforeStart do
  @moduledoc """
  Remove from the activity before the start (#895 E), a step: what was the Remove
  members page (#704) without its tick tables, since the team admin picked the members
  on the Members tab. With nobody checked signed up, nobody gets an email, so there's
  nothing to ask: the tab removes them in place, after a confirm. From the start,
  Web.ActivityMembersLive.Remove does it in place.

  Two tables: who goes with no email, then who goes and gets the team admin's message.
  A checked signed up member with an email needs that message, which SAR Duty emails
  them; one with no email gets nothing, and the step says to tell them. A team admin who
  told them already sends no email only once they select the box that says they meant
  it, as with their own chores (#697); the message is then optional, for History. With
  nobody to email, the message and the preview go. RemoveMembers.call/7 checks again on
  send: each member goes only with the reply the tab showed.
  """
  @behaviour Web.ActivityMembersLive.Action

  use Web, :live_component

  import Web.Components.Columns, only: [member_cell: 1]
  import Web.Components.EmailPreview
  import Web.Components.Table, only: [table: 1]

  alias App.Mailer.ActivityMailer
  alias App.Model.Activity
  alias App.Operation.RemoveMembers
  alias App.Operation.SendReminders
  alias App.Validate.Message
  alias Service.Format
  alias Web.ActivityMembersLive.Action
  alias Web.Components.Reply

  @impl Action
  def value, do: "remove"

  @impl Action
  def label, do: "Remove from the activity"

  @impl Action
  def hint(_ctx), do: "Members who signed up get your message."

  # Before the start, on an activity neither deleted nor published.
  @impl Action
  def offered?(%{activity: activity, now: now}),
    do: Activity.open?(activity, now) and not activity.is_published

  @impl Action
  def count(_ctx, checked), do: length(checked)

  @impl Action
  def button_text(count),
    do: Format.count(count, one: "Remove 1 member", many: "Remove %d members")

  @impl Action
  def variant, do: :danger

  # With someone signed up, the step asks, once it knows who gets an email.
  @impl Action
  def confirm(%{activity: activity}, checked) do
    if signed_up?(checked),
      do: %{},
      else: %{
        "data-confirm" =>
          "Remove #{members_text(length(checked))} from #{activity.title}? Nobody gets an email. To undo, add them again."
      }
  end

  @impl Action
  def run(checked),
    do: if(signed_up?(checked), do: {:step, :remove}, else: {:in_place, :remove_before_start})

  defp signed_up?(checked), do: Enum.any?(checked, &(&1.status == "attending"))

  # The rows are the checked members as the step opened; later renders keep them.
  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    first? = !Map.has_key?(socket.assigns, :rows)
    socket = assign(socket, assigns)
    {:ok, if(first?, do: load(socket), else: socket)}
  end

  defp load(socket) do
    %{team: team, user: user, checked: checked} = socket.assigns

    socket
    |> assign(
      rows: checked,
      sender: SendReminders.sender(team, user, DateTime.utc_now()),
      message: "",
      message_error: nil,
      skip_email: false
    )
    |> assign_emailed()
  end

  # The signed up members who need a message, who of them gets it by email, and those
  # SAR Duty can't email.
  defp assign_emailed(%{assigns: %{rows: rows, skip_email: skip_email}} = socket) do
    {messaged, no_email} = rows |> signed_up() |> Enum.split_with(&RemoveMembers.email?/1)
    emailed = if skip_email, do: [], else: messaged
    ids = MapSet.new(emailed, & &1.id)
    {emailed_rows, other_rows} = Enum.split_with(rows, &MapSet.member?(ids, &1.member.id))

    socket
    |> assign(
      messaged: messaged,
      emailed: emailed,
      no_email: no_email,
      emailed_rows: emailed_rows,
      other_rows: other_rows
    )
    |> assign_preview()
  end

  # The signed up members, by name.
  defp signed_up(rows) do
    for(%{status: "attending"} = row <- rows, do: row.member)
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp assign_preview(socket) do
    %{activity: activity, team: team, sender: sender, message: message} = socket.assigns

    assign(
      socket,
      :preview,
      ActivityMailer.removal_preview(activity, team, sender, Message.normalize(message))
    )
  end

  # The message box keeps its error until the team admin types in it.
  @impl Phoenix.LiveComponent
  def handle_event("change", params, socket) do
    %{message: message, message_error: message_error} = socket.assigns
    new_message = Map.get(params, "message", message)

    {:noreply,
     socket
     |> assign(
       message: new_message,
       message_error: if(new_message == message, do: message_error),
       skip_email: params["skip_email"] == "true"
     )
     |> assign_emailed()}
  end

  # The ids are the step's, never the browser's, each with the reply the tab showed, so
  # RemoveMembers skips anyone whose reply changed since. On the activity as it is now,
  # which may have started or been published.
  def handle_event("remove", params, socket) do
    %{team: team, user: user, rows: rows} = socket.assigns
    activity = Web.ActivityLive.fetch_activity(team, socket.assigns.activity.id)
    message = Map.get(params, "message", "")
    checked = for row <- rows, do: {row.member.id, row.status}
    opts = [email: params["skip_email"] != "true"]

    team
    |> RemoveMembers.call(activity, checked, message, user, DateTime.utc_now(), opts)
    |> outcome(socket, message)
  end

  # The tab with a toast, or the step again with the error on the message box.
  defp outcome({:ok, result}, socket, _message) do
    send(self(), {:step_done, flash_kind(result), RemoveMembers.result_text(result)})
    {:noreply, socket}
  end

  defp outcome({:error, reason}, socket, message)
       when reason in [:no_message, :message_too_long] do
    text = RemoveMembers.error_text(socket.assigns.team, reason)
    send(self(), {:step_flash, :error, text})
    {:noreply, assign(socket, message: message, message_error: text)}
  end

  defp outcome({:error, reason}, socket, _message) do
    send(self(), {:step_done, :error, RemoveMembers.error_text(socket.assigns.team, reason)})
    {:noreply, socket}
  end

  # Anyone not removed needs another look, so the toast stays.
  defp flash_kind(%{not_removed: []}), do: :info
  defp flash_kind(_result), do: :error

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="remove-step">
      <p id="remove-intro" class="measure">
        SAR Duty takes them off the activity. To undo, add them again: they come back with No reply and answer again.
      </p>

      <.form for={%{}} id="remove-form" phx-change="change" phx-submit="remove" phx-target={@myself}>
        <div :if={@other_rows != []} class="measure mt-6">
          <.removed_table
            id="remove-no-email-table"
            label="Removed, no email"
            rows={@other_rows}
            team={@team}
            standings={@standings}
          />
        </div>
        <div :if={@emailed_rows != []} class="measure mt-6">
          <.warning_text id="remove-signed-up-warning" class="mb-4">
            Each gets your message by email, because they signed up.
          </.warning_text>
          <.removed_table
            id="remove-emailed-table"
            label="Removed and emailed your message"
            rows={@emailed_rows}
            team={@team}
            standings={@standings}
          />
        </div>

        <div :if={@messaged != []} class="measure mt-6">
          <.input
            id="remove-message"
            name="message"
            type="textarea"
            label={message_label(@messaged, @skip_email)}
            value={@message}
            errors={List.wrap(@message_error)}
            rows="4"
            maxlength={Message.max_length()}
            phx-debounce="300"
          >
            <%= if @skip_email do %>
              Nobody gets an email. The activity's history keeps it. Up to {Message.limit_text()}.
            <% else %>
              Required to remove a signed up member. SAR Duty emails it, and the activity's history keeps it. Up to {Message.limit_text()}.
            <% end %>
          </.input>
          <.input
            type="checkbox"
            id="remove-skip-email"
            name="skip_email"
            value={@skip_email}
            label="Remove without emailing them"
          >
            I know members who signed up should get my message by email. I'm making an exception.
          </.input>
        </div>

        <p :if={@no_email != []} id="remove-no-email" class="hint measure mt-6">
          {if @emailed == [], do: "Nobody gets an email. "}{names(@no_email)} {has(@no_email)} no email in {@service}, so tell them yourself.
        </p>

        <section :if={@emailed != []} id="remove-preview-section" class="mt-8">
          <h2 class="subheading">{preview_title(@emailed)}</h2>
          <p class="hint mb-3">
            From {@team.name}. Replies come to you at {@sender.email}.
          </p>
          <.email_preview subject={@preview.subject} html={@preview.html} />
        </section>

        <.form_actions class="mt-8">
          <.button
            id="remove-send"
            variant={:danger}
            phx-disable-with="Removing…"
            data-confirm-needs={@messaged != [] and !@skip_email and "#remove-message"}
            {confirm(@activity, @rows, @emailed)}
          >
            {button_text(length(@rows))}
          </.button>
          <.button id="remove-back" patch={@back}>Back</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :rows, :list, required: true
  attr :team, :any, required: true
  attr :standings, :map, required: true

  # Who goes, headed by what they get, with each one's reply.
  defp removed_table(assigns) do
    ~H"""
    <.table id={@id} rows={@rows} row_id={&"remove-row-#{&1.member.id}"} class="table-striped">
      <:col :let={row} label={@label}>
        <.member_cell member={row.member} team={@team} standing={@standings[row.member.id]} />
      </:col>
      <:col :let={row} label="Reply" class="whitespace-nowrap">
        {reply_text(row, @team.timezone)}
      </:col>
    </.table>
    """
  end

  # "Signed up Nov 3, 12:09", "Can't make it", or "No reply".
  defp reply_text(%{status: "attending", replied_at: %DateTime{} = at}, timezone),
    do: "Signed up " <> Format.month_day_time(at, timezone)

  defp reply_text(row, _timezone), do: Reply.status_text(row.status, false)

  # Asks only when someone gets an email, as Send an update does. It names who does, and
  # counts the rest by reply, so clearing 60 No reply rows lists no names.
  defp confirm(_activity, _rows, []), do: %{}

  defp confirm(activity, rows, emailed) do
    question = "Remove #{members_text(length(rows))} from #{activity.title}?"
    others = Enum.reject(rows, &(&1.member in emailed))

    lines =
      [
        "#{names(emailed)} signed up, and #{if length(emailed) == 1, do: "gets", else: "get"} your email.",
        others_text(others)
      ]
      |> Enum.reject(&is_nil/1)

    send_confirm(length(emailed), question, lines)
  end

  defp others_text([]), do: nil

  defp others_text(others) do
    counts =
      for status <- ["requested", "absent", "attending"],
          n = Enum.count(others, &(&1.status == status)),
          n > 0,
          do: "#{n} #{String.downcase(Reply.status_text(status, false))}"

    who = others |> length() |> Format.count(one: "1 other gets", many: "%d others get")
    "#{who} no email: #{Enum.join(counts, ", ")}."
  end

  defp message_label(members, false = _skip_email), do: "Message to #{to_text(members)}"
  defp message_label(members, true), do: "Why you removed #{to_text(members)} (optional)"

  defp to_text([member]), do: member.name
  defp to_text(members), do: "#{length(members)} signed up members"

  defp preview_title([member]), do: "What #{member.name} gets"
  defp preview_title(_members), do: "What they get"

  defp has([_one]), do: "has"
  defp has(_many), do: "have"

  defp members_text(count), do: Format.count(count, one: "%d member", many: "%d members")

  defp names(members), do: members |> Enum.map(& &1.name) |> Format.and_list()
end
