defmodule Web.ReplyLinkLive do
  use Web, :live_view_narrow_layout

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Repo
  alias Service.Format
  alias Web.Components.Reply
  alias Web.Components.ReplyControl
  alias Web.ReplyLinks

  # The page a reminder's buttons open (#444): no login, only the link's token, for one
  # member and one activity. Opening it changes nothing, since some mail apps open every
  # link; the member selects a button. It takes replies until the activity starts, and
  # always offers the activity's own page, which needs a login.
  def mount(%{"token" => token}, _session, socket) do
    now = DateTime.utc_now()

    socket =
      case find(token) do
        {member, activity} ->
          assign(socket,
            page_title: activity.title,
            member: member,
            activity: activity,
            team: activity.team,
            invitation: Attendance.invitation(activity, member),
            now: now
          )

        nil ->
          assign(socket, page_title: "This link does not work", activity: nil)
      end

    {:ok, socket}
  end

  # The member and the activity, both on the same team, or nil.
  defp find(token) do
    with {:ok, {member_id, activity_id}} <- ReplyLinks.verify_reply(token),
         %Member{} = member <- Repo.get(Member, member_id),
         %Activity{} = activity <-
           Activity.get_by(id: activity_id, team_id: member.team_id) do
      {member, Repo.preload(activity, :team)}
    else
      _missing -> nil
    end
  end

  defp activity_path(team, activity), do: ~p"/teams/#{team}/activities/#{activity.id}"

  def handle_info({:replied, attendance}, socket),
    do: {:noreply, assign(socket, invitation: attendance)}

  def handle_info({:reply_failed, text}, socket), do: {:noreply, put_flash(socket, :error, text)}

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

    <div class="mt-6">
      <.live_component
        :if={Reply.open?(@invitation, @activity, @now)}
        module={ReplyControl}
        id="reply-link"
        team={@team}
        activity={@activity}
        member={@member}
        invitation={@invitation}
        user={nil}
      />
      <p :if={@activity.deleted_at} id="reply-link-deleted">
        This activity is deleted in {D4H.service_name(@team)}.
      </p>
      <p
        :if={@invitation && !@activity.deleted_at && !Reply.open?(@invitation, @activity, @now)}
        id="reply-link-closed"
      >
        Replies closed when it started.
      </p>
    </div>

    <p :if={!@activity.deleted_at} class="mt-6 mb-0">
      <.a id="reply-link-open" href={activity_path(@team, @activity)}>Open activity</.a>
      <span class="hint">(log in)</span>
    </p>
    """
  end
end
