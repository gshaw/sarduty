defmodule Web.PhotoAskLive do
  use Web, :live_view_app_layout

  import Web.Components.Table, only: [table: 1]

  alias App.Model.Member
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Operation.AskForPhoto
  alias App.Validate.Message
  alias Service.Format
  alias Web.PhotoCollectionLive

  # Ask for a photo, /teams/:subdomain/photos/members/ask (#1030), built like Ask for a
  # reply on an activity: who gets an email, why the rest do not, an optional message,
  # and one send. `?member=<id>` asks that member, for a first photo, a new one, or
  # again. Without it the page asks every current member with no photo, an email, and no
  # ask still open. AskForPhoto.plan/4 decides who, and its call/5 plans again on send.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    if !Team.photos?(team), do: raise(Web.Status.NotFound)

    member = if id = params["member"], do: Member.find!(team, id)
    now = DateTime.utc_now()
    plan = AskForPhoto.load_plan(team, member || :everyone, now)

    {:ok,
     assign(socket,
       page_title: title(member),
       member: member,
       plan: plan,
       standings: Standing.by_member(team, Enum.map(plan.send, & &1.member), now),
       back: back(team, member),
       form: to_form(%{"message" => ""})
     )}
  end

  defp title(nil), do: "Ask for photos"
  defp title(_member), do: "Ask for a photo"

  @doc "The page that asks `member`, or everyone with no photo when nil."
  def path(team, nil), do: ~p"/teams/#{team}/photos/members/ask"
  def path(team, member), do: ~p"/teams/#{team}/photos/members/ask?#{[member: member.id]}"

  # Where Cancel goes, and sending lands: the member's ID Card tab, or Photos.
  defp back(team, nil), do: PhotoCollectionLive.view_path(team, :members)
  defp back(team, member), do: ~p"/teams/#{team}/members/#{member.id}/card"

  def handle_event("change", %{"message" => message}, socket),
    do: {:noreply, assign(socket, form: to_form(%{"message" => message}))}

  # Who is asked is the plan as it stands now, never the page's.
  def handle_event("send", %{"message" => message}, socket) do
    %{current_team: team, current_user: user, member: member, back: back} = socket.assigns

    case AskForPhoto.call(team, user, member || :everyone, message, DateTime.utc_now()) do
      {:ok, []} ->
        {:noreply, socket |> put_flash(:error, "Nobody was emailed.") |> push_navigate(to: back)}

      {:ok, asks} ->
        text =
          asks |> length() |> Format.count(one: "%d member asked.", many: "%d members asked.")

        {:noreply, socket |> put_flash(:info, text) |> push_navigate(to: back)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(form: to_form(%{"message" => message}))
         |> put_flash(:error, AskForPhoto.error_text(reason))}
    end
  end

  def render(assigns) do
    assigns = assign(assigns, count: length(assigns.plan.send))

    ~H"""
    <.breadcrumbs>
      <:item label="Photos" path={PhotoCollectionLive.path(@current_team)} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>
    <p id="ask-lead" class="lead measure">
      {@current_team.name} emails each member a link to add a photo. It needs no login.
    </p>

    <.form for={@form} id="ask-form" phx-change="change" phx-submit="send">
      <section id="ask-who">
        <h2 class="subheading">Who gets it</h2>
        <p :if={@count == 0} id="ask-nobody">
          {if @member,
            do: "Nobody to email now.",
            else: "Every member has a photo or has been asked."}
        </p>
        <.table
          :if={@count > 0}
          id="ask-to"
          rows={@plan.send}
          row_id={&"ask-to-#{&1.member.id}"}
          class="table-striped w-fit"
        >
          <:col :let={row} label="Member">
            <.member_cell
              member={row.member}
              team={@current_team}
              standing={@standings[row.member.id]}
            />
          </:col>
          <:col :let={row} label="Email">{row.member.email}</:col>
        </.table>
        <%!-- Only one member is ever asked again: asking everyone leaves out the asked. --%>
        <p :for={%{ask: %{} = ask} <- @plan.send} id="ask-before" class="hint mt-2">
          Asked before, on {Format.date_short(ask.asked_at, @current_team.timezone)}.
        </p>
      </section>

      <.left_out left_out={@plan.left_out} timezone={@current_team.timezone} />

      <div :if={@count > 0} class="measure mt-8">
        <.input
          field={@form[:message]}
          id="ask-message"
          type="textarea"
          label="Message (optional)"
          rows="4"
          maxlength={Message.max_length()}
          phx-debounce="300"
        >
          Your own words, at the top of the email.
        </.input>
      </div>

      <.form_actions class="mt-8">
        <.button
          :if={@count > 0}
          id="ask-send"
          variant={:primary}
          phx-disable-with="Sending…"
          {send_confirm(@count, "Email #{members_text(@count)} to ask for a photo?", [
            "Each gets a link to add a photo, with no login."
          ])}
        >
          {Format.count(@count, one: "Ask %d member", many: "Ask %d members")}
        </.button>
        <.button id="ask-cancel" navigate={@back}>Cancel</.button>
      </.form_actions>
    </.form>
    """
  end

  defp members_text(count), do: Format.count(count, one: "%d member", many: "%d members")

  attr :left_out, :list, required: true
  attr :timezone, :string, required: true

  # Everyone the plan leaves out, a line per reason: a count of who has a photo, and the
  # names of the rest.
  defp left_out(assigns) do
    assigns = assign(assigns, lines: lines(assigns.left_out, assigns.timezone))

    ~H"""
    <section :if={@lines != []} id="ask-left-out" class="mt-8">
      <h2 class="subheading">Who does not get it</h2>
      <ul class="list-disc pl-6 space-y-1">
        <li :for={{id, text} <- @lines} id={id}>{text}</li>
      </ul>
    </section>
    """
  end

  # `[{id, "No email: Riley Okafor."}]`, in a set order. Members asked are grouped by the
  # day they were asked, oldest first.
  defp lines(left_out, timezone) do
    reasons = Enum.group_by(left_out, & &1.reason)

    has_photo_lines(reasons[:has_photo]) ++
      named_lines(reasons) ++ asked_lines(reasons[:asked] || [], timezone)
  end

  defp has_photo_lines(nil), do: []

  defp has_photo_lines(rows),
    do: [{"left-out-has-photo", "Has a photo: #{rows |> length() |> members_text()}."}]

  defp named_lines(reasons) do
    for {reason, label} <- [
          no_email: "No email",
          retiring: "Retiring",
          not_a_person: "Not a person"
        ],
        rows = reasons[reason] do
      {"left-out-#{reason}", "#{label}: #{names(rows)}."}
    end
  end

  defp asked_lines(rows, timezone) do
    rows
    |> Enum.sort_by(& &1.ask.asked_at, DateTime)
    |> Enum.chunk_by(&Format.month_day(&1.ask.asked_at, timezone))
    |> Enum.with_index(fn [first | _rest] = rows, index ->
      {"left-out-asked-#{index}",
       "Asked #{Format.month_day(first.ask.asked_at, timezone)}: #{names(rows)}."}
    end)
  end

  defp names(rows), do: rows |> Enum.map(& &1.member.name) |> Format.and_list()
end
