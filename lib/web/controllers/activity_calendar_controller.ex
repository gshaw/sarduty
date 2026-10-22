defmodule Web.ActivityCalendarController do
  use Web, :controller

  alias App.Adapter.D4H
  alias App.Model.Activity

  # Add to calendar (#389, #406): an .ics file for an activity, for anyone on the team who
  # sees it. A member gets only the activities they see (Activity.visible_to_member/3).
  def show(conn, %{"id" => id}) do
    %{current_team: team, current_member: member, team_admin?: team_admin?} = conn.assigns
    now = DateTime.utc_now()

    activity =
      if team_admin?,
        do:
          Activity
          |> Activity.not_deleted()
          |> Activity.scope(team_id: team.id)
          |> App.Repo.get!(id),
        else: Activity.find_visible!(member, id, now)

    ics =
      Service.Calendar.event(
        %{
          uid: "activity-#{activity.id}@sarduty.com",
          title: activity.title,
          starts_at: activity.started_at,
          ends_at: activity.finished_at,
          location: activity.address,
          url: if(!D4H.records?(team), do: D4H.activity_url(team, activity))
        },
        now
      )

    send_download(conn, {:binary, ics},
      filename: "#{team.subdomain}-activity-#{activity.id}.ics",
      content_type: "text/calendar"
    )
  end
end
