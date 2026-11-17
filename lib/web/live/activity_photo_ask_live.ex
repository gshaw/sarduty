defmodule Web.ActivityPhotoAskLive do
  use Web, :live_view_app_layout

  import Web.Components.Table, only: [table: 1]

  alias App.Model.Standing
  alias App.Operation.AskForActivityPhotos
  alias App.Validate.Message
  alias Service.Format
  alias Web.ActivityLive

  # Ask for photos, /teams/:subdomain/activities/:id/photos/ask (#1034), built like Ask
  # for a photo (Web.PhotoAskLive): who gets an email, why the rest do not, an optional
  # message, and one send. It asks every member who attended, has an email, has added
  # no photo to the activity, and takes these emails. AskForActivityPhotos.plan/4
  # decides who, and its call/5 plans again on send. Not found on an activity nobody is
  # asked about (askable?/3): an incident, one yet to start, or a team with no activity
  # photos.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    activity = ActivityLive.fetch_activity(team, id)
    now = DateTime.utc_now()
    if !AskForActivityPhotos.askable?(team, activity, now), do: raise(Web.Status.NotFound)

    plan = AskForActivityPhotos.load_plan(team, activity, now)

    {:ok,
     assign(socket,
       page_title: "#{activity.title} · Ask for photos",
       activity: activity,
       plan: plan,
       standings: Standing.by_member(team, plan.send, now),
       back: Web.ActivityPhoto.tab_path(team, activity.id),
       form: to_form(%{"message" => ""})
     )}
  end

  @doc "The page that asks everyone who attended the activity."
  def path(team, activity_id), do: ~p"/teams/#{team}/activities/#{activity_id}/photos/ask"

  def handle_event("change", %{"message" => message}, socket),
    do: {:noreply, assign(socket, form: to_form(%{"message" => message}))}

  # Who is asked is the plan as it stands now, never the page's.
  def handle_event("send", %{"message" => message}, socket) do
    %{current_team: team, current_user: user, back: back} = socket.assigns
    activity = ActivityLive.fetch_activity(team, socket.assigns.activity.id)

    case AskForActivityPhotos.call(team, activity, user, message, DateTime.utc_now()) do
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
         |> put_flash(:error, AskForActivityPhotos.error_text(reason))}
    end
  end

  def render(assigns) do
    assigns = assign(assigns, count: length(assigns.plan.send))

    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        label={@activity.ref_id}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label="Photos" path={@back} />
      <:item label="Ask for photos" />
    </.breadcrumbs>
    <h1 class="title">Ask for photos</h1>
    <p id="ask-lead" class="lead measure">
      {@current_team.name} emails each member who attended a link to add their photos. It needs no login.
    </p>

    <.form for={@form} id="ask-form" phx-change="change" phx-submit="send">
      <section id="ask-who">
        <h2 class="subheading">Who gets it</h2>
        <p :if={@count == 0} id="ask-nobody">
          Everyone who attended has added photos or cannot be emailed.
        </p>
        <.table
          :if={@count > 0}
          id="ask-to"
          rows={@plan.send}
          row_id={&"ask-to-#{&1.id}"}
          class="table-striped w-fit"
        >
          <:col :let={member} label="Member">
            <.member_cell member={member} team={@current_team} standing={@standings[member.id]} />
          </:col>
          <:col :let={member} label="Email">{member.email}</:col>
        </.table>
      </section>

      <.left_out left_out={@plan.left_out} />

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
          {send_confirm(@count, "Email #{members_text(@count)} to ask for photos?", [
            "Each gets a link to add their photos from #{@activity.title}, with no login."
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

  # Who attended and gets no email, a line per reason, by name. Members who did not
  # attend are never listed: that is the rest of the activity's list. Nor is a retiring
  # member, who is no longer a member.
  defp left_out(assigns) do
    reasons = Enum.group_by(assigns.left_out, & &1.reason, & &1.member.name)

    lines =
      for {reason, label} <- [
            added: "Added photos",
            no_email: "No email",
            asks_off: "Turned photo asks off"
          ],
          names = reasons[reason] do
        {"left-out-#{reason}", "#{label}: #{Format.and_list(names)}."}
      end

    assigns = assign(assigns, lines: lines)

    ~H"""
    <section :if={@lines != []} id="ask-left-out" class="mt-8">
      <h2 class="subheading">Who does not get it</h2>
      <ul class="list-disc pl-6 space-y-1">
        <li :for={{id, text} <- @lines} id={id}>{text}</li>
      </ul>
    </section>
    """
  end
end
