defmodule Web.ReplyLinkLive do
  use Web, :live_view_narrow_layout

  import Web.Components.Reply, only: [reply: 1]

  alias App.Model.Attendance
  alias Service.Format
  alias Web.Components.Reply
  alias Web.ReplyLinks

  # The page a reminder's buttons open (#444): no login, only the link's token, for one
  # member and one activity. Opening it changes nothing, since some mail apps open every
  # link. It's a form with the email's answer selected (#488), posted to
  # Web.ReplyLinkController, so Send reply works before the page connects. It takes
  # replies until the activity starts, and always offers the activity's own page, which
  # needs a login.
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case ReplyLinks.find_reply(token) do
        {member, activity} ->
          assign(socket,
            page_title: activity.title,
            token: token,
            activity: activity,
            team: activity.team,
            invitation: Attendance.invitation(activity, member),
            now: DateTime.utc_now()
          )

        nil ->
          assign(socket, page_title: "This link does not work", activity: nil)
      end

    {:ok, socket}
  end

  # `reply` is the email button the member came from; `change` is Change after sending.
  def handle_params(params, _uri, %{assigns: %{activity: nil}} = socket),
    do: {:noreply, assign(socket, params: params)}

  def handle_params(params, _uri, socket) do
    current = current_answer(socket.assigns.invitation)
    asked = answer(params["reply"])
    changing? = params["change"] == "1"
    form? = current == nil or changing? or (asked != nil and asked != current)

    {:noreply,
     assign(socket,
       current: current,
       form?: form?,
       form: to_form(%{"reply" => answer_param(asked || current)}),
       # Their reply now, when the email asks to change it.
       was: if(form? and current != nil and not changing?, do: current)
     )}
  end

  # Their reply now, `:yes` or `:no`, or nil before they reply.
  defp current_answer(invitation) do
    case Reply.state(invitation, false) do
      :ask -> nil
      answer -> answer
    end
  end

  defp answer("yes"), do: :yes
  defp answer("no"), do: :no
  defp answer(_other), do: nil

  defp answer_param(nil), do: nil
  defp answer_param(answer), do: Atom.to_string(answer)

  defp activity_path(team, activity), do: ~p"/teams/#{team}/activities/#{activity.id}"

  def render(%{activity: nil} = assigns) do
    ~H"""
    <h1 class="title">This link does not work</h1>
    <p>Log in to reply to the activity.</p>
    <p>
      <.a id="reply-link-login" navigate={~p"/login"}>Log in</.a>
    </p>
    """
  end

  def render(assigns) do
    ~H"""
    <p class="hint mb-1">{@team.name}</p>
    <h1 class="title mb-2">{@activity.title}</h1>
    <p id="reply-link-when" class="mb-0">
      {Format.datetime_medium(@activity.started_at, @team.timezone)}
    </p>
    <p :if={@activity.address} class="mb-0">{@activity.address}</p>

    <div :if={Reply.open?(@invitation, @activity, @now)} class="mt-6">
      <.form
        :if={@form?}
        for={@form}
        id="reply-link-form"
        class="reply-form"
        action={~p"/replies/#{@token}"}
        method="post"
      >
        <fieldset>
          <legend>Will you be there?</legend>
          <p :if={@was} id="reply-link-was" class="hint mb-2">
            Your reply: {Reply.status_text(@invitation.status, false)}
          </p>
          <label class="choice">
            <input
              type="radio"
              id="reply-link-yes"
              name={@form[:reply].name}
              value="yes"
              checked={@form[:reply].value == "yes"}
            /> I'll be there
          </label>
          <label class="choice">
            <input
              type="radio"
              id="reply-link-no"
              name={@form[:reply].name}
              value="no"
              checked={@form[:reply].value == "no"}
            /> Can't make it
          </label>
        </fieldset>
        <.button id="reply-link-send" type="submit" variant={:primary}>Send reply</.button>
      </.form>
      <.reply
        :if={!@form?}
        id="reply-link"
        state={@current}
        change_href={~p"/replies/#{@token}?change=1"}
        calendar_href={~p"/replies/#{@token}/calendar"}
      />
    </div>
    <p :if={@activity.deleted_at} id="reply-link-deleted" class="mt-6">
      This activity is deleted.
    </p>
    <p
      :if={@invitation && !@activity.deleted_at && !Reply.open?(@invitation, @activity, @now)}
      id="reply-link-closed"
      class="mt-6"
    >
      Replies closed when it started.
    </p>

    <p :if={!@activity.deleted_at} class="mt-6 mb-0">
      <.a id="reply-link-open" href={activity_path(@team, @activity)}>Open activity</.a>
      <span class="hint">(log in)</span>
    </p>
    """
  end
end
