defmodule App.Adapter.D4H do
  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Team

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

  def build_context_from_team(%Team{} = team) do
    build_context(
      access_key: team.d4h_access_key,
      api_host: team.d4h_api_host,
      d4h_team_id: team.d4h_team_id
    )
  end

  def build_context(access_key: access_key, api_host: api_host, d4h_team_id: d4h_team_id) do
    Req.new(
      base_url: "https://#{api_host}/v3/team/#{d4h_team_id}",
      headers: %{"User-Agent" => "sarduty.com"},
      auth: {:bearer, access_key || ""},
      # Req 0.6+ no longer asks for gzip by default. api_host is always one of
      # D4H.regions(), so decompressing is safe, and 1000-record pages are large.
      compressed: true
    )
    |> Req.Request.put_private(:d4h_team_id, d4h_team_id)
  end

  def determine_team_id(access_key: access_key, api_host: api_host) do
    case fetch_whoami(access_key: access_key, api_host: api_host) do
      {:ok, whoami} -> {:ok, whoami.d4h_team_id}
      error -> error
    end
  end

  def fetch_whoami(access_key: access_key, api_host: api_host) do
    context =
      Req.new(
        base_url: "https://#{api_host}/v3",
        headers: %{"User-Agent" => "sarduty.com"},
        auth: {:bearer, access_key || ""}
      )

    response = Req.get!(context, url: "/whoami")

    with 200 <- response.status,
         %D4H.WhoAmI{} = whoami <- D4H.WhoAmI.build(response.body) do
      {:ok, whoami}
    else
      _ -> {:error, "Unable to determine team ID"}
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
    with {:ok, image_document} <- D4H.fetch_team_image_document(context) do
      download_document(context, image_document.d4h_document_id, "team.png")
    end
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
    context
    |> fetch_all("/members", &D4H.Member.build/1)
    |> Enum.sort(&(&1.name < &2.name))
  end

  def reduce_attendances(context, acc, fun) do
    reduce_pages(context, "/attendance", &D4H.AttendanceInfo.build/1, acc, fun)
  end

  def reduce_activities(context, tag_index, kind, acc, fun) do
    reduce_pages(context, "/#{kind}", &D4H.Activity.build(&1, tag_index), acc, fun)
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
    fetch_all(context, "/member-qualifications", &D4H.Qualification.build/1)
  end

  def reduce_qualification_awards(context, acc, fun) do
    reduce_pages(
      context,
      "/member-qualification-awards",
      &D4H.QualificationAward.build/1,
      acc,
      fun
    )
  end

  def fetch_groups(context) do
    fetch_all(context, "/member-groups", &D4H.Group.build/1)
  end

  def reduce_group_memberships(context, acc, fun) do
    reduce_pages(context, "/member-group-memberships", &D4H.GroupMembership.build/1, acc, fun)
  end

  def fetch_tags(context) do
    fetch_all(context, "/tags", &D4H.Tag.build/1)
  end

  defp fetch_all(context, url, build) do
    context
    |> reduce_pages(url, build, [], &[&1 | &2])
    |> Enum.reverse()
    |> Enum.concat()
  end

  # Calls `fun` with each page of built rows, then raises unless the rows add up to
  # D4H's totalSize. The refresh deletes whatever D4H didn't return, so a short fetch
  # must never look like a finished one.
  defp reduce_pages(context, url, build, acc, fun) do
    request = %{context: context, url: url, build: build}
    reduce_from_page(request, 0, 0, acc, fun)
  end

  defp reduce_from_page(request, page_number, fetched_count, acc, fun) do
    page = fetch_page!(request, page_number)
    fetched_count = fetched_count + length(page.results)
    rows = Enum.map(page.results, request.build)
    acc = fun.(rows, acc)

    case D4H.Page.next(page, fetched_count) do
      :done ->
        acc

      :next ->
        reduce_from_page(request, page_number + 1, fetched_count, acc, fun)

      :short ->
        raise D4H.Error,
              "D4H returned #{fetched_count} of #{page.total_size} records from #{request.url}."
    end
  end

  defp fetch_page!(request, page_number) do
    params = [page: page_number, size: 1000]
    response = Req.get!(request.context, url: request.url, params: params)

    with 200 <- response.status,
         {:ok, page} <- D4H.Page.build(response.body) do
      page
    else
      _ -> raise D4H.Error, response
    end
  end

  defp update_attendance(context, attendance_id, status) do
    Req.patch!(context, url: "/attendance/#{attendance_id}", json: %{status: status})
  end

  def add_attendance(context, attendance_id),
    do: update_attendance(context, attendance_id, "ATTENDING")

  def remove_attendance(context, attendance_id),
    do: update_attendance(context, attendance_id, "ABSENT")
end
