defmodule App.Adapter.D4H do
  alias App.Accounts.User
  alias App.Adapter.D4H

  def default_region, do: "api.ca.d4h.org"

  def regions do
    %{
      "America" => "api.d4h.org",
      "Canada" => "api.ca.d4h.org",
      "Europe" => "api.eu.d4h.org",
      "Pacific" => "api.ap.d4h.org",
      "Staging" => "api.st.d4h.org"
    }
  end

  # TODO: rename build_ with team_, e.g., team_url(@current_team, "/dashboard")
  def build_url(team, path \\ "/dashboard") do
    team_manager_host =
      team.d4h_api_host
      |> String.replace("api.", "#{team.subdomain}.team-manager.")
      |> String.replace(".org", ".com")

    "https://#{team_manager_host}#{path}"
  end

  def activity_url(team, activity) do
    activity_path =
      case activity.activity_kind do
        "incident" -> "incidents"
        "event" -> "events"
        "exercise" -> "exercises"
      end

    build_url(team, "/team/#{activity_path}/view/#{activity.d4h_activity_id}")
  end

  def member_url(member) do
    build_url(member.team, "/team/members/view/#{member.d4h_member_id}")
  end

  def determine_region(api_host) do
    regions()
    |> Enum.find(fn {_key, val} -> val == api_host end)
    |> elem(0)
  end

  def build_context_from_user(%User{} = user) do
    build_context(
      access_key: user.d4h_access_key,
      api_host: user.team.d4h_api_host,
      d4h_team_id: user.team.d4h_team_id
    )
  end

  def build_context(access_key: access_key, api_host: api_host, d4h_team_id: d4h_team_id) do
    Req.new(
      base_url: "https://#{api_host}/v3/team/#{d4h_team_id}",
      headers: %{"User-Agent" => "sarduty.com"},
      auth: {:bearer, access_key || ""}
    )
    |> Req.Request.put_private(:d4h_team_id, d4h_team_id)
  end

  def determine_team_id(access_key: access_key, api_host: api_host) do
    context =
      Req.new(
        base_url: "https://#{api_host}/v3",
        headers: %{"User-Agent" => "sarduty.com"},
        auth: {:bearer, access_key || ""}
      )

    response = Req.get!(context, url: "/whoami")

    if response.status == 200 do
      whoami = D4H.WhoAmI.build(response.body)
      {:ok, whoami.d4h_team_id}
    else
      {:error, "Unable to determine team ID"}
    end
  end

  def fetch_member_image(context, member_id) do
    response =
      Req.get!(context, url: "/members/#{member_id}/image", params: [size: "PREVIEW"])

    if response.status == 200 do
      {:ok, response.body, "member-#{member_id}.png"}
    else
      {:error, response}
    end
  end

  def fetch_team_image_document(context) do
    response =
      Req.get!(context,
        url: "/documents",
        params: [
          profile: true,
          target_resource_type: "Team"
        ]
      )

    if response.status == 200 do
      result = response.body["results"] |> List.first()
      {:ok, D4H.Document.build(result)}
    else
      {:error, response}
    end
  end

  def download_document(context, document_id, file_name) do
    response =
      Req.get!(context, url: "/documents/#{document_id}/download")

    if response.status == 200 do
      {:ok, response.body, file_name}
    else
      {:error, response}
    end
  end

  def fetch_team_image(context) do
    {:ok, image_document} = D4H.fetch_team_image_document(context)
    download_document(context, image_document.d4h_document_id, "team.png")
  end

  def fetch_team(context) do
    d4h_team_id = Req.Request.get_private(context, :d4h_team_id)
    response = Req.get!(context, url: "/teams/#{d4h_team_id}")

    if response.status == 200 do
      {:ok, D4H.Team.build(response.body)}
    else
      {:error, response}
    end
  end

  def fetch_team_members(context) do
    response = Req.get!(context, url: "/members", params: [size: -1])

    response.body["results"]
    |> Enum.map(&D4H.Member.build(&1))
    |> Enum.sort(&(&1.name < &2.name))
  end

  def fetch_attendances(context, page) do
    response = Req.get!(context, url: "/attendance", params: [page: page, size: 1000])

    response.body["results"]
    |> Enum.map(&D4H.AttendanceInfo.build(&1))
  end

  def fetch_activities(context, tag_index, kind, page) do
    response = Req.get!(context, url: "/#{kind}", params: [page: page, size: 1000])

    response.body["results"]
    |> Enum.map(&D4H.Activity.build(&1, tag_index))
  end

  def fetch_activity(context, activity_id, "event") do
    response = Req.get!(context, url: "/events/#{activity_id}")

    response.body
    |> D4H.Activity.build()
  end

  def fetch_activity(context, activity_id, "incident") do
    response = Req.get!(context, url: "/incidents/#{activity_id}")

    response.body
    |> D4H.Activity.build()
  end

  def fetch_activity(context, activity_id, "exercise") do
    response = Req.get!(context, url: "/exercises/#{activity_id}")

    response.body
    |> D4H.Activity.build()
  end

  def fetch_activity_attendance(context, activity_id, team_members) do
    response = Req.get!(context, url: "/attendance", params: [activity_id: activity_id])

    response.body["results"]
    |> Enum.map(&D4H.Attendance.build(&1, team_members))
    |> Enum.sort(&(&1.member.name < &2.member.name))
  end

  def fetch_qualifications(context) do
    response = Req.get!(context, url: "/member-qualifications", params: [size: -1])

    response.body["results"]
    |> Enum.map(&D4H.Qualification.build(&1))
  end

  def fetch_qualification_awards(context, page) do
    response =
      Req.get!(context, url: "/member-qualification-awards", params: [page: page, size: 1000])

    response.body["results"]
    |> Enum.map(&D4H.QualificationAward.build(&1))
  end

  def fetch_tags(context) do
    response = Req.get!(context, url: "/tags", params: [size: -1])
    response.body["results"] |> Enum.map(&D4H.Tag.build(&1))
  end

  defp update_attendance(context, attendance_id, status) do
    Req.patch!(context, url: "/attendance/#{attendance_id}", json: %{status: status})
  end

  def add_attendance(context, attendance_id),
    do: update_attendance(context, attendance_id, "ATTENDING")

  def remove_attendance(context, attendance_id),
    do: update_attendance(context, attendance_id, "ABSENT")
end
