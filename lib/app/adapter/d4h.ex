defmodule App.Adapter.D4H do
  alias App.Adapter.D4H
  alias App.Model.Team

  require Logger

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

  def build_context_from_team(%Team{} = team) do
    build_context(
      access_key: team.d4h_access_key,
      api_host: team.d4h_api_host,
      d4h_team_id: team.d4h_team_id
    )
  end

  def build_context(access_key: access_key, api_host: api_host, d4h_team_id: d4h_team_id) do
    [
      base_url: "https://#{api_host}/v3/team/#{d4h_team_id}",
      headers: %{"User-Agent" => "sarduty.com"},
      auth: {:bearer, access_key || ""},
      # Req 0.6+ no longer asks for gzip by default. api_host is always one of
      # D4H.regions(), so decompressing is safe, and 1000-record pages are large.
      compressed: true
    ]
    |> Keyword.merge(test_options())
    |> Req.new()
    |> Req.Request.put_private(:d4h_team_id, d4h_team_id)
    |> report_rate_limits()
  end

  # D4H sends no rate-limit headers, so a 429 is the only sign of a limit. This step goes
  # ahead of Req's retry, which would otherwise retry it unseen. Honeybadger groups them
  # into one error, and its first email is the cue to slow down.
  defp report_rate_limits(request),
    do: Req.Request.prepend_response_steps(request, d4h_rate_limit: &report_rate_limit/1)

  @doc false
  def report_rate_limit({request, %Req.Response{status: 429} = response}) do
    details = %{
      d4h_team_id: Req.Request.get_private(request, :d4h_team_id),
      host: request.url.host,
      path: request.url.path,
      retry_after: response |> Req.Response.get_header("retry-after") |> List.first()
    }

    Logger.warning("D4H rate limit (429): #{inspect(details)}")

    response
    |> D4H.Error.exception()
    |> Honeybadger.notify(metadata: details, fingerprint: "d4h-429")

    {request, response}
  end

  def report_rate_limit({request, response}), do: {request, response}

  # config/test.exs routes every request to `Req.Test`, so no test reaches D4H.
  defp test_options, do: Application.get_env(:sarduty, App.Adapter.D4H, [])

  def determine_team_id(access_key: access_key, api_host: api_host) do
    case fetch_whoami(access_key: access_key, api_host: api_host) do
      {:ok, whoami} -> {:ok, whoami.d4h_team_id}
      error -> error
    end
  end

  def fetch_whoami(access_key: access_key, api_host: api_host) do
    context =
      [
        base_url: "https://#{api_host}/v3",
        headers: %{"User-Agent" => "sarduty.com"},
        auth: {:bearer, access_key || ""}
      ]
      |> Keyword.merge(test_options())
      |> Req.new()
      |> report_rate_limits()

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
      case List.first(response.body["results"]) do
        nil -> {:ok, nil}
        result -> {:ok, D4H.Document.build(result)}
      end
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

  # `:none` when the team has no profile image in D4H.
  def fetch_team_image(context) do
    case D4H.fetch_team_image_document(context) do
      {:ok, nil} -> :none
      {:ok, document} -> download_document(context, document.d4h_document_id, "team.png")
      error -> error
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

  @page_size 1000

  # Pages fetched at once. D4H sent no rate-limit headers, and 4 at a time took a full
  # attendance list from 35 s to 15 s with no errors (#163).
  @concurrency 4

  # Calls `fun` with each page of built rows, in order, then raises unless the rows add
  # up to D4H's totalSize. The refresh deletes whatever D4H didn't return, so a short
  # fetch must never look like a finished one. Page 0 gives the total; the rest are
  # fetched 4 at a time, while `fun` runs here.
  defp reduce_pages(context, url, build, acc, fun, params \\ []) do
    request = %{context: context, url: url, params: params}
    first = fetch_page!(request, 0)
    rest = D4H.Page.count(first, @page_size) - 1

    pages =
      1..rest//1
      |> Task.async_stream(&fetch_page(request, &1),
        max_concurrency: @concurrency,
        timeout: :timer.minutes(2)
      )
      |> Stream.map(fn {:ok, result} -> page!(result) end)

    {acc, fetched_count} =
      [first]
      |> Stream.concat(pages)
      |> Enum.reduce({acc, 0}, fn page, {acc, count} ->
        rows = Enum.map(page.results, build)
        {fun.(rows, acc), count + length(page.results)}
      end)

    if D4H.Page.check(first, fetched_count) == :short do
      raise D4H.Error, "D4H returned #{fetched_count} of #{first.total_size} records from #{url}."
    end

    acc
  end

  defp fetch_page!(request, page_number), do: request |> fetch_page(page_number) |> page!()

  # Returns rather than raises, so an error in a task reaches the caller as D4H.Error.
  defp fetch_page(request, page_number, size \\ @page_size) do
    params = [page: page_number, size: size] ++ request.params
    response = Req.get!(request.context, url: request.url, params: params)

    with 200 <- response.status,
         {:ok, page} <- D4H.Page.build(response.body) do
      {:ok, page}
    else
      _ -> {:error, D4H.Error.exception(response)}
    end
  end

  defp page!({:ok, page}), do: page
  defp page!({:error, error}), do: raise(error)

  # Finding what changed, for the sync every 10 minutes (#163). Every list sorts by
  # updatedAt, so its newest row and its total tell whether anything changed since the
  # last look.

  @doc """
  A list's total and its newest change, as `%{total_size: n, newest_updated_at: dt}`,
  from one row sorted by `updatedAt`. `newest_updated_at` is nil for an empty list.
  """
  def fetch_list_head(context, url, params \\ []) do
    request = %{context: context, url: url, params: [sort: "updatedAt", order: "desc"] ++ params}
    page = request |> fetch_page(0, 1) |> page!()

    newest =
      case page.results do
        [row | _] -> D4H.Parse.optional_datetime(row["updatedAt"])
        [] -> nil
      end

    %{total_size: page.total_size, newest_updated_at: newest}
  end

  @doc "How many attendance rows start in `[starts_after, starts_before)`."
  def fetch_attendance_count(context, starts_after, starts_before) do
    params = [starts_after: iso(starts_after), starts_before: iso(starts_before)]
    request = %{context: context, url: "/attendance", params: params}
    page = request |> fetch_page(0, 1) |> page!()
    page.total_size
  end

  @doc "Every attendance row that starts in `[starts_after, starts_before)`, in pages."
  def reduce_attendances_between(context, starts_after, starts_before, acc, fun) do
    params = [starts_after: iso(starts_after), starts_before: iso(starts_before)]
    reduce_pages(context, "/attendance", &D4H.AttendanceInfo.build/1, acc, fun, params)
  end

  @doc "Activities of one kind changed after `updated_after`, in pages."
  def reduce_activities_updated_after(context, tag_index, kind, updated_after, acc, fun) do
    build = &D4H.Activity.build(&1, tag_index)
    params = [updated_after: iso(updated_after)]
    reduce_pages(context, "/#{kind}", build, acc, fun, params)
  end

  @doc """
  D4H ids of activities of one kind deleted after `updated_after`. A deleted activity's
  `updatedAt` is at or after its `deletedAt`, so new deletes show up here.
  """
  def fetch_deleted_activity_ids(context, kind, updated_after) do
    params = [deleted: true, updated_after: iso(updated_after)]

    context
    |> reduce_pages("/#{kind}", & &1["id"], [], &[&1 | &2], params)
    |> Enum.concat()
  end

  @doc """
  Attendance rows changed at or after `since`, newest first. D4H's attendance has no
  `updated_after`, so this pages by `updatedAt` descending and stops at the first row
  older than `since`.
  """
  def fetch_attendances_changed_since(context, since) do
    request = %{context: context, url: "/attendance", params: [sort: "updatedAt", order: "desc"]}
    fetch_changed_pages(request, since, 0, [])
  end

  defp fetch_changed_pages(request, since, page_number, acc) do
    page = request |> fetch_page(page_number) |> page!()
    rows = Enum.map(page.results, &D4H.AttendanceInfo.build/1)
    {newer, older} = Enum.split_while(rows, &(DateTime.compare(&1.updated_at, since) != :lt))
    acc = acc ++ newer

    if older != [] or page.results == [] or (page_number + 1) * @page_size >= page.total_size,
      do: acc,
      else: fetch_changed_pages(request, since, page_number + 1, acc)
  end

  # Only App.Operation.ApplyChangeSet calls the writes below: add_group_member,
  # remove_group_membership, set_attendance, and create_attendance (#174).
  #
  # The two group writes return D4H.Error instead of raising, so one failed change
  # doesn't stop the rest. Neither is retried: a person is watching and can apply
  # again, and a retried POST could add someone twice.
  def add_group_member(context, d4h_group_id, d4h_member_id) do
    request = [
      method: :post,
      url: "/member-group-memberships",
      json: %{groupId: d4h_group_id, memberId: d4h_member_id},
      retry: false
    ]

    case Req.request(context, request) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, D4H.GroupMembership.build(response.body)}

      result ->
        {:error, write_error(result)}
    end
  end

  # A membership D4H has already deleted counts as removed.
  def remove_group_membership(context, d4h_group_membership_id) do
    request = [
      method: :delete,
      url: "/member-group-memberships/#{d4h_group_membership_id}",
      retry: false
    ]

    case Req.request(context, request) do
      {:ok, %{status: status}} when status in 200..299 or status == 404 -> :ok
      result -> {:error, write_error(result)}
    end
  end

  defp write_error({:ok, response}), do: D4H.Error.exception(response)

  defp write_error({:error, exception}),
    do: exception |> Exception.message() |> D4H.Error.exception()

  # Taking attendance at the door (#139) reads an activity's attendance fresh before it
  # writes. D4H accepts a second POST for a member who already has a row and counts
  # their hours twice, so a write must know what is there now. None of these retry.

  @doc "Whether D4H has published the activity now, as `{:ok, boolean}`."
  def fetch_activity_published(context, d4h_activity_id, kind)
      when kind in ["event", "exercise", "incident"] do
    case Req.request(context, method: :get, url: "/#{kind}s/#{d4h_activity_id}", retry: false) do
      {:ok, %{status: 200, body: %{"published" => published}}} -> {:ok, published == true}
      result -> {:error, write_error(result)}
    end
  end

  @doc "Every attendance row on the activity now, as `D4H.AttendanceInfo` structs."
  def fetch_attendance_infos(context, d4h_activity_id) do
    request = [
      method: :get,
      url: "/attendance",
      params: [activity_id: d4h_activity_id, size: 1000],
      retry: false
    ]

    with {:ok, %{status: 200, body: body} = response} <- Req.request(context, request),
         {:ok, page} <- D4H.Page.build(body),
         true <- length(page.results) == page.total_size || {:short, response} do
      {:ok, Enum.map(page.results, &D4H.AttendanceInfo.build/1)}
    else
      {:short, response} -> {:error, D4H.Error.exception(response)}
      :error -> {:error, D4H.Error.exception("D4H sent no attendance list.")}
      result -> {:error, write_error(result)}
    end
  end

  @doc """
  Marks an existing attendance row attending, with times, or absent. Attending without
  times keeps the row's times.
  """
  def set_attendance(context, d4h_attendance_id, "ATTENDING", nil, nil) do
    json = %{status: "ATTENDING"}
    write_attendance(context, :patch, "/attendance/#{d4h_attendance_id}", json)
  end

  def set_attendance(context, d4h_attendance_id, "ATTENDING", starts_at, ends_at) do
    json = %{status: "ATTENDING", startsAt: iso(starts_at), endsAt: iso(ends_at)}
    write_attendance(context, :patch, "/attendance/#{d4h_attendance_id}", json)
  end

  def set_attendance(context, d4h_attendance_id, "ABSENT", _starts_at, _ends_at),
    do: write_attendance(context, :patch, "/attendance/#{d4h_attendance_id}", %{status: "ABSENT"})

  @doc "Adds an attending row for a member D4H has no row for: a walk-in."
  def create_attendance(context, d4h_activity_id, d4h_member_id, starts_at, ends_at) do
    json = %{
      activityId: d4h_activity_id,
      memberId: d4h_member_id,
      status: "ATTENDING",
      startsAt: iso(starts_at),
      endsAt: iso(ends_at)
    }

    write_attendance(context, :post, "/attendance", json)
  end

  defp write_attendance(context, method, url, json) do
    case Req.request(context, method: method, url: url, json: json, retry: false) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, D4H.AttendanceInfo.build(response.body)}

      result ->
        {:error, write_error(result)}
    end
  end

  defp iso(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
