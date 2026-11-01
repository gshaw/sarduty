defmodule Web.ActivityRemoveMembersLive do
  use Web, :live_view_app_layout

  import Web.Components.EmailPreview

  alias App.Adapter.D4H
  alias App.Mailer.ActivityMailer
  alias App.Model.Activity
  alias App.Model.Standing
  alias App.Operation.RemoveMembers
  alias App.Operation.SendReminders
  alias App.Validate.Message
  alias App.ViewData.ActivityMembers
  alias Service.Format
  alias Web.Components.Reply

  # Taking members off an activity (#704), laid out like Send an update: a table per
  # reply, each with select all, and nothing checked. No reply and Can't make it come
  # first, since removing them emails nobody. A checked signed up member with an email
  # needs the team admin's message, which SAR Duty emails them; one with no email gets
  # nothing, and the page says to tell them. Only before the start, on an activity
  # neither deleted nor published.
  def mount(%{"id" => id}, _session, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    activity = Web.ActivityLive.fetch_activity(team, id)
    now = DateTime.utc_now()

    case Activity.adding(activity, true, now) do
      :open ->
        {:ok,
         socket
         |> assign(
           page_title: "Remove members",
           activity: activity,
           sender: SendReminders.sender(team, user, now),
           selected: MapSet.new(),
           message: "",
           now: now
         )
         |> assign_rows(ActivityMembers.load(activity))
         |> assign_checked()}

      _closed ->
        {:ok, leave(socket, activity, now)}
    end
  end

  # Each member's reply as the page shows it, which RemoveMembers checks again.
  defp assign_rows(socket, rows) do
    %{current_team: team, now: now} = socket.assigns

    assign(socket,
      groups: groups(rows),
      shown: Map.new(rows, &{&1.member.id, &1.status}),
      members: Map.new(rows, &{&1.member.id, &1.member}),
      standings: Standing.by_member(team, Enum.map(rows, & &1.member), now)
    )
  end

  # No reply first, then Can't make it, then Signed up, each only when someone has it.
  defp groups(rows) do
    for status <- ["requested", "absent", "attending"],
        group = Enum.filter(rows, &(&1.status == status)),
        group != [],
        do: {status, group}
  end

  # Who of the checked gets an email, and the signed up members who can't.
  defp assign_checked(socket) do
    %{selected: selected, shown: shown, members: members} = socket.assigns
    checked = for id <- selected, member = members[id], do: {member, shown[id]}
    signed_up = for {member, "attending"} <- checked, do: member
    {emailed, no_email} = Enum.split_with(signed_up, &RemoveMembers.email?/1)

    socket
    |> assign(
      checked: checked,
      emailed: Enum.sort_by(emailed, &String.downcase(&1.name)),
      no_email: Enum.sort_by(no_email, &String.downcase(&1.name))
    )
    |> assign_preview()
  end

  defp assign_preview(socket) do
    %{activity: activity, current_team: team, sender: sender, message: message} =
      socket.assigns

    assign(
      socket,
      :preview,
      ActivityMailer.removal_preview(activity, team, sender, Message.normalize(message))
    )
  end

  # A stale visitor goes back to the activity, as Add members sends them.
  defp leave(socket, %Activity{deleted_at: %DateTime{}} = activity, _now),
    do: Web.ActivityLive.leave_deleted(socket, activity)

  defp leave(socket, activity, now) do
    text =
      if Activity.started?(activity, now),
        do: "The activity has started, so nobody can be removed here.",
        else: "Published, so nobody can be removed. #{D4H.unpublish_text(activity.team)}"

    socket
    |> put_flash(:error, text)
    |> push_navigate(to: activity_path(socket, activity))
  end

  def handle_event("change", params, socket) do
    {:noreply,
     socket
     |> assign(
       selected: params |> selected_ids() |> MapSet.new(),
       message: Map.get(params, "message", socket.assigns.message)
     )
     |> assign_checked()}
  end

  # Each id with the status the page showed for it, so RemoveMembers skips anyone whose
  # reply changed since.
  def handle_event("remove", params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns
    checked = checked_ids(params, socket.assigns.shown)

    case RemoveMembers.call(team, activity, checked, params["message"], user, DateTime.utc_now()) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(flash_kind(result), RemoveMembers.result_text(result))
         |> push_navigate(to: activity_path(socket, activity))}

      {:error, :deleted} ->
        {:noreply, Web.ActivityLive.leave_deleted(socket, activity)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, RemoveMembers.error_text(team, reason))}
    end
  end

  # Swoosh's test adapter tells each process an email came from, this one included.
  def handle_info({:email, _email}, socket), do: {:noreply, socket}

  defp checked_ids(params, shown),
    do: for(id <- selected_ids(params), status = shown[id], do: {id, status})

  # Anyone not removed needs another look, so the toast stays.
  defp flash_kind(%{not_removed: []}), do: :info
  defp flash_kind(_result), do: :error

  # Ids come from the browser; only members the page showed go on.
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
      <:item label="Remove members" />
    </.breadcrumbs>
    <h1 class="title">Remove members</h1>
    <p class="lead">
      {@activity.title} · {Format.datetime_medium(@activity.started_at, @current_team.timezone)}
    </p>
    <p id="remove-intro" class="measure">
      SAR Duty takes them off the activity in {@service}. To undo, add them again: they come back with No reply and answer again.
    </p>

    <p :if={@groups == []} id="remove-nobody">Nobody is on the activity.</p>

    <.form :if={@groups != []} for={%{}} id="remove-form" phx-change="change" phx-submit="remove">
      <div :for={{status, rows} <- @groups} class="measure mb-6">
        <.warning_text :if={status == "attending"} id="remove-signed-up-warning" class="mb-4">
          They told you they're coming. Each one you remove gets your message by email, unless {@service} has no email for them.
        </.warning_text>
        <.table
          id={"remove-#{status}"}
          rows={rows}
          row_id={&"remove-row-#{&1.member.id}"}
          class="table-striped"
        >
          <:col :let={row} label="" class="w-px" select_all>
            <input
              type="checkbox"
              id={"remove-select-#{row.member.id}"}
              name="member_ids[]"
              value={row.member.id}
              checked={MapSet.member?(@selected, row.member.id)}
            />
          </:col>
          <:col :let={row} label={Reply.status_text(status, false)}>
            <.member_cell
              member={row.member}
              team={@current_team}
              standing={@standings[row.member.id]}
              label_for={"remove-select-#{row.member.id}"}
            />
          </:col>
          <:col :let={row} :if={status != "requested"} label="Replied" class="whitespace-nowrap">
            {Format.month_day_time(row.replied_at, @current_team.timezone)}
            <.badge
              :if={ActivityMembers.new?(row, @now)}
              kind={:primary}
              title="Replied in the last 24 hours"
            >
              New
            </.badge>
          </:col>
          <:col :let={row} :if={status == "attending"} label="">
            <span :if={!RemoveMembers.email?(row.member)} class="hint">
              No email in {@service}, so tell them yourself
            </span>
          </:col>
        </.table>
      </div>

      <div :if={@emailed != []} class="measure">
        <.input
          id="remove-message"
          name="message"
          type="textarea"
          label={"Message to #{to_text(@emailed)}"}
          value={@message}
          rows="4"
          maxlength={Message.max_length()}
          phx-debounce="300"
        >
          Required to remove a signed up member. SAR Duty emails it, and the activity's history keeps it. Up to {Message.limit_text()}.
        </.input>
      </div>

      <p :if={@no_email != []} id="remove-no-email" class="hint measure">
        {if @emailed == [], do: "Nobody gets an email. "}{names(@no_email)} {has(@no_email)} no email in {@service}, so tell them yourself.
      </p>

      <section :if={@emailed != []} id="remove-preview-section" class="mt-8">
        <h2 class="subheading">{preview_title(@emailed)}</h2>
        <p class="hint mb-3">
          From {@current_team.name}. Replies come to you at {@sender.email}.
        </p>
        <.email_preview subject={@preview.subject} html={@preview.html} />
      </section>

      <.form_actions class="mt-8">
        <.button
          id="remove-send"
          variant={:danger}
          disabled={@checked == []}
          phx-disable-with="Removing…"
          {confirm(@activity, @checked, @emailed)}
        >
          {remove_text(length(@checked))}
        </.button>
        <.button id="remove-cancel" navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}"}>
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

  # Asks only when someone gets an email, as Send an update does. It names who does, and
  # counts the rest by reply, so clearing 60 No reply rows lists no names.
  defp confirm(_activity, _checked, []), do: %{}

  defp confirm(activity, checked, emailed) do
    question = "Remove #{members_text(length(checked))} from #{activity.title}?"
    others = Enum.reject(checked, fn {member, _status} -> member in emailed end)

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
          n = Enum.count(others, &(elem(&1, 1) == status)),
          n > 0,
          do: "#{n} #{String.downcase(Reply.status_text(status, false))}"

    who = others |> length() |> Format.count(one: "1 other gets", many: "%d others get")
    "#{who} no email: #{Enum.join(counts, ", ")}."
  end

  defp remove_text(0), do: "Remove members"

  defp remove_text(count),
    do: Format.count(count, one: "Remove 1 member", many: "Remove %d members")

  defp to_text([member]), do: member.name
  defp to_text(members), do: "#{length(members)} signed up members"

  defp preview_title([member]), do: "What #{member.name} gets"
  defp preview_title(_members), do: "What they get"

  defp has([_one]), do: "has"
  defp has(_many), do: "have"

  defp members_text(count), do: Format.count(count, one: "%d member", many: "%d members")

  defp names(members), do: members |> Enum.map(& &1.name) |> Format.and_list()
end
