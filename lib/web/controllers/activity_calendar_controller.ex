defmodule Web.ActivityCalendarController do
  use Web, :controller

  alias App.Adapter.D4H
  alias App.Model.Activity

  # Add to calendar (#389, #406): an .ics file for any of the team's activities that D4H
  # still has, for anyone on the team.
  def show(conn, %{"id" => id}) do
    team = conn.assigns.current_team
    now = DateTime.utc_now()

    activity =
      Activity
      |> Activity.not_deleted()
      |> Activity.scope(team_id: team.id)
      |> App.Repo.get!(id)

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
