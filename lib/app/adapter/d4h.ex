defmodule App.Adapter.D4H do
  alias App.Adapter.D4H

  def build_context(access_token: access_token, api_host: api_host) do
    Req.new(
      base_url: "https://#{api_host}/v2/",
      headers: %{"User-Agent" => "sarduty.com"},
      auth: {:bearer, access_token}
    )
  end

  def build_context(_current_user) do
    build_context(
      access_token: System.get_env("D4H_ACCESS_TOKEN"),
      api_host: "api.ca.d4h.org"
    )
  end

  def fetch_team(context) do
    context
    |> Req.get!(url: "/team")
    |> D4H.Team.build()
  end

  def fetch_team_members(context) do
    response = Req.get!(context, url: "/team/members")

    response.body["data"]
    |> Enum.map(&D4H.Member.build(&1))
    |> Enum.sort(&(&1.name < &2.name))
  end

  def fetch_activites(context),
    do: fetch_activites(context, params: [limit: 50, sort: "date:desc", before: "now"])

  def fetch_activites(context, params: params) do
    response = Req.get!(context, url: "/team/activities", params: params)

    response.body["data"]
    |> Enum.map(&D4H.Activity.build(&1))
  end

  def fetch_activity(context, activity_id) do
    response = Req.get!(context, url: "/team/activities/#{activity_id}")

    response.body["data"]
    |> D4H.Activity.build()
  end

  def fetch_activity_attendance(context, activity_id, team_members) do
    response = Req.get!(context, url: "/team/attendance", params: [activity_id: activity_id])

    response.body["data"]
    |> Enum.map(&D4H.Attendance.build(&1, team_members))
    |> Enum.sort(&(&1.member.name < &2.member.name))
  end

  defp update_attendance(context, attendance_id, status) do
    context
    |> Req.put!(url: "/team/attendance/#{attendance_id}", form: [status: status])
  end

  def add_attendance(context, attendance_id),
    do: update_attendance(context, attendance_id, "attending")

  def remove_attendance(context, attendance_id),
    do: update_attendance(context, attendance_id, "absent")
end
