defmodule App.Adapter.D4H do
  alias App.Adapter.D4H
  alias App.Model.Event
  alias App.Model.Team

  require Logger

  def default_region, do: "api.ca.d4h.org"

  # SAR Duty Records (docs/records.md) keeps a team's records when it has no D4H. It
  # serves D4H's v3 API, with a few writes D4H lacks, so a team on it is called through
  # this adapter like any other.
  @records_host "records.sarduty.com"

  @doc "The host of SAR Duty Records. Dev can point it elsewhere with RECORDS_HOST."
  def records_host, do: Application.get_env(:sarduty, :records_host, @records_host)

  @doc """
  The services a team's records can live in, as `{label, api_host}` for a select: each
  D4H region, then SAR Duty Records. SAR Duty only ever calls these hosts.
  """
  def services do
    regions()
    |> Enum.sort()
    |> Enum.map(fn {region, host} -> {"D4H #{region}", host} end)
    |> Enum.concat([{"SAR Duty Records (experimental)", records_host()}])
  end

  def service_hosts, do: Enum.map(services(), &elem(&1, 1))

  @doc "Where a team's records live: `:d4h` or `:records`. Takes a team, an api host, or either atom."
  def service(%Team{d4h_api_host: api_host}), do: service(api_host)
  def service(api_host) when is_binary(api_host) or is_nil(api_host), do: service_of(api_host)
  def service(service) when service in [:d4h, :records], do: service

  defp service_of(api_host) do
    if api_host == records_host(), do: :records, else: :d4h
  end

  def records?(team_or_host), do: service(team_or_host) == :records

  @doc ~s(The service's name in text people read: "D4H" or "SAR Duty Records".)
  def service_name(team_or_host) do
    case service(team_or_host) do
      :d4h -> "D4H"
      :records -> "SAR Duty Records"
    end
  end

  @doc ~s(The team's key, in text people read: "D4H access key" or "Records access key".)
  def key_name(team_or_host) do
    case service(team_or_host) do
      :d4h -> "D4H access key"
      :records -> "Records access key"
    end
  end

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
    [access_key: team.d4h_access_key, api_host: team.d4h_api_host, d4h_team_id: team.d4h_team_id]
    |> build_context()
    |> Req.Request.put_private(:team_id, team.id)
  end

  def build_context(access_key: access_key, api_host: api_host, d4h_team_id: d4h_team_id) do
    [
      base_url: "https://#{api_host}/v3/team/#{d4h_team_id}",
      headers: %{"User-Agent" => "sarduty.com"},
      auth: {:bearer, access_key || ""},
      # Req 0.6+ no longer asks for gzip by default. api_host is always one of
      # D4H.services(), so decompressing is safe, and 1000-record pages are large.
      compressed: true
    ]
    |> Keyword.merge(test_options())
    |> Req.new()
    |> Req.Request.put_private(:d4h_team_id, d4h_team_id)
    |> report_rate_limits()
  end

  # D4H sends no rate-limit headers, so a 429 is the only sign of a limit. This step goes
  # ahead of Req's retry, which would otherwise retry it unseen. Honeybadger groups them
  # into one error, and its first email is the cue to slow down; the event counts them.
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

    Event.record!(:d4h_rate_limited,
      team_id: Req.Request.get_private(request, :team_id),
      data: details
    )

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

  # One page, sized past any activity's attendance; D4H's spec gives no default size.
  def fetch_activity_attendance(context, activity_id, team_members) do
    response =
      Req.get!(context, url: "/attendance", params: [activity_id: activity_id, size: 1000])

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

  @doc """
  Every equipment item, with its kind and location titles (#271). D4H answers 403 for
  a team without its equipment module, which raises D4H.Error like any failure.
  """
  def fetch_equipment_items(context) do
    kinds = context |> fetch_all("/equipment-kinds", &{&1["id"], &1["title"]}) |> Map.new()

    locations =
      context |> fetch_all("/equipment-locations", &{&1["id"], &1["title"]}) |> Map.new()

    fetch_all(context, "/equipment", &D4H.EquipmentItem.build(&1, kinds, locations))
  end

  def fetch_equipment_usages(context),
    do: fetch_all(context, "/equipment-usages", &D4H.EquipmentUsage.build/1)

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
        # Not truncated: Records can make two changes within a second, and they must
        # still look different.
        [row | _] -> D4H.Parse.precise_datetime(row["updatedAt"])
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
  D4H ids of every activity of one kind D4H lists, which leaves out deleted ones. The
  sync compares them to find deletes: D4H's `deleted=true` list comes back empty for a
  service account's key (tested 2026-10-07), though a person's key sees it.
  """
  def fetch_activity_ids(context, kind) do
    context
    |> reduce_pages("/#{kind}", & &1["id"], [], &[&1 | &2])
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
  # remove_group_membership, set_attendance, create_attendance, and the equipment
  # usage writes (#174).
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

  @doc "A member's address and emergency contacts now, as `D4H.MemberDetails` (#156)."
  def fetch_member_details(context, d4h_member_id) do
    case Req.request(context, method: :get, url: "/members/#{d4h_member_id}", retry: false) do
      {:ok, %{status: 200, body: body}} -> {:ok, D4H.MemberDetails.build(body)}
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

  @doc "Every equipment usage on the activity now, as `D4H.EquipmentUsage` structs."
  def fetch_activity_equipment_usages(context, d4h_activity_id) do
    request = [
      method: :get,
      url: "/equipment-usages",
      params: [activity_id: d4h_activity_id, size: 1000],
      retry: false
    ]

    with {:ok, %{status: 200, body: body} = response} <- Req.request(context, request),
         {:ok, page} <- D4H.Page.build(body),
         true <- length(page.results) == page.total_size || {:short, response} do
      {:ok, Enum.map(page.results, &D4H.EquipmentUsage.build/1)}
    else
      {:short, response} -> {:error, D4H.Error.exception(response)}
      :error -> {:error, D4H.Error.exception("D4H sent no equipment usage list.")}
      result -> {:error, write_error(result)}
    end
  end

  @doc """
  Adds an item to an activity's equipment. `minutes` goes as the usage's duration, which
  D4H takes only for equipment; nil sends none.
  """
  def create_equipment_usage(context, d4h_activity_id, d4h_equipment_id, minutes) do
    json =
      %{activityId: d4h_activity_id, equipmentId: d4h_equipment_id}
      |> then(&if(minutes, do: Map.put(&1, :duration, minutes), else: &1))

    write(context, :post, "/equipment-usages", json, &D4H.EquipmentUsage.build/1)
  end

  @doc "Removes an item from an activity's equipment. A usage D4H has already deleted counts."
  def delete_equipment_usage(context, d4h_equipment_usage_id) do
    request = [method: :delete, url: "/equipment-usages/#{d4h_equipment_usage_id}", retry: false]

    case Req.request(context, request) do
      {:ok, %{status: status}} when status in 200..299 or status == 404 -> :ok
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

  # Editing records, for a team on SAR Duty Records (docs/records.md). ApplyChangeSet
  # calls these for a change set of source :edit. `attrs` have SAR Duty's names, with
  # string keys and times as ISO 8601 strings, as change set rows store them; only the
  # keys given are sent. Some are Records' own, and D4H would refuse them.

  @member_fields %{
    "name" => "name",
    "ref_id" => "ref",
    "position" => "position",
    "email" => "email",
    "address" => "deprecatedAddress",
    "status" => "status",
    "joined_at" => "startsAt",
    # Only Records takes this. D4H sets access in its web app.
    "permission" => "permission"
  }

  @doc "Adds a member. POST /members is Records' own; D4H adds members in its web app."
  def create_member(context, attrs),
    do: write(context, :post, "/members", member_json(attrs), &D4H.Member.build/1)

  def update_member(context, d4h_member_id, attrs),
    do:
      write(context, :patch, "/members/#{d4h_member_id}", member_json(attrs), &D4H.Member.build/1)

  @doc "Marks a member as left on `left_at`, as D4H's retire does."
  def retire_member(context, d4h_member_id, left_at) do
    json = %{date: left_at, direction: "RETIRE"}
    write(context, :patch, "/members/#{d4h_member_id}/retire", json, &D4H.Member.build/1)
  end

  def rejoin_member(context, d4h_member_id) do
    json = %{direction: "UNRETIRE"}
    write(context, :patch, "/members/#{d4h_member_id}/retire", json, &D4H.Member.build/1)
  end

  @activity_fields %{
    "title" => "referenceDescription",
    "description" => "description",
    "tracking_number" => "trackingNumber",
    "started_at" => "startsAt",
    "finished_at" => "endsAt"
  }

  @doc """
  Adds an activity of `kind` ("event", "exercise", or "incident"), then sets its tags and
  published flag when `attrs` name them.
  """
  def create_activity(context, kind, attrs) when kind in ["event", "exercise", "incident"] do
    with {:ok, activity} <-
           write(context, :post, "/#{kind}s", activity_json(attrs), &D4H.Activity.build/1) do
      # The activity exists now, so this answers with it whatever its tags and published
      # flag do: a failed create would be tried again and make a second one.
      case finish_activity(context, kind, activity.d4h_activity_id, attrs) do
        {:ok, finished} ->
          {:ok, finished}

        {:error, error} ->
          Logger.warning(
            "Activity #{activity.d4h_activity_id} added without its tags or published flag: #{Exception.message(error)}"
          )

          {:ok, activity}
      end
    end
  end

  def update_activity(context, kind, d4h_activity_id, attrs)
      when kind in ["event", "exercise", "incident"] do
    url = "/#{kind}s/#{d4h_activity_id}"

    with {:ok, _activity} <-
           write(context, :patch, url, activity_json(attrs), &D4H.Activity.build/1) do
      finish_activity(context, kind, d4h_activity_id, attrs)
    end
  end

  @doc "Deletes an activity. DELETE is Records' own; D4H has no delete in its API."
  def delete_activity(context, kind, d4h_activity_id)
      when kind in ["event", "exercise", "incident"],
      do:
        write(context, :delete, "/#{kind}s/#{d4h_activity_id}", nil, fn _body ->
          d4h_activity_id
        end)

  defp finish_activity(context, kind, d4h_activity_id, attrs) do
    url = "/#{kind}s/#{d4h_activity_id}"
    build = &D4H.Activity.build/1

    with {:ok, activity} <-
           maybe_write(
             attrs,
             "tag_ids",
             &write(context, :post, url <> "/tags", %{tagIds: &1}, build)
           ),
         {:ok, activity} <-
           maybe_write(
             attrs,
             "published",
             &write(context, :post, url <> "/publish", %{published: &1}, build),
             activity
           ) do
      {:ok, activity || %D4H.Activity{d4h_activity_id: d4h_activity_id}}
    end
  end

  defp maybe_write(attrs, key, write, previous \\ nil) do
    if Map.has_key?(attrs, key), do: write.(attrs[key]), else: {:ok, previous}
  end

  def create_qualification(context, title),
    do:
      write(context, :post, "/member-qualifications", %{title: title}, &D4H.Qualification.build/1)

  def update_qualification(context, d4h_qualification_id, title) do
    url = "/member-qualifications/#{d4h_qualification_id}"
    write(context, :patch, url, %{title: title}, &D4H.Qualification.build/1)
  end

  @doc "Deletes a qualification and its awards. DELETE is Records' own, not D4H's."
  def delete_qualification(context, d4h_qualification_id) do
    url = "/member-qualifications/#{d4h_qualification_id}"
    write(context, :delete, url, nil, fn _body -> d4h_qualification_id end)
  end

  @doc "Awards a qualification from `starts_at` to `ends_at`, nil for no expiry."
  def award_qualification(context, d4h_qualification_id, d4h_member_id, starts_at, ends_at) do
    json = %{
      qualificationId: d4h_qualification_id,
      memberId: d4h_member_id,
      startsAt: starts_at,
      endsAt: ends_at
    }

    write(context, :post, "/member-qualification-awards", json, &D4H.QualificationAward.build/1)
  end

  @doc "Removes an award. DELETE is Records' own, not D4H's."
  def remove_award(context, d4h_award_id) do
    url = "/member-qualification-awards/#{d4h_award_id}"
    write(context, :delete, url, nil, fn _body -> d4h_award_id end)
  end

  def create_group(context, title),
    do: write(context, :post, "/member-groups", %{title: title}, &D4H.Group.build/1)

  def update_group(context, d4h_group_id, title),
    do:
      write(
        context,
        :patch,
        "/member-groups/#{d4h_group_id}",
        %{title: title},
        &D4H.Group.build/1
      )

  def delete_group(context, d4h_group_id),
    do:
      write(context, :delete, "/member-groups/#{d4h_group_id}", nil, fn _body -> d4h_group_id end)

  defp activity_json(attrs) do
    json = rename(attrs, @activity_fields)

    if Map.has_key?(attrs, "place"),
      do:
        Map.put(json, "address", %{street: attrs["place"], town: nil, region: nil, country: nil}),
      else: json
  end

  @doc """
  Sets a member's photo to `bytes`, a JPEG, PNG, or WebP. PUT on the image is Records'
  own; D4H takes photos only in its web app. Records shrinks it and strips its metadata.
  """
  def set_member_photo(context, d4h_member_id, bytes) when is_binary(bytes) do
    url = "/members/#{d4h_member_id}/image"
    write(context, :put, url, {:body, bytes}, &D4H.Member.build/1)
  end

  @doc "Removes a member's photo. DELETE on the image is Records' own."
  def remove_member_photo(context, d4h_member_id),
    do: write(context, :delete, "/members/#{d4h_member_id}/image", nil, &D4H.Member.build/1)

  defp member_json(attrs) do
    attrs
    |> rename(@member_fields)
    |> then(fn json ->
      if Map.has_key?(attrs, "phone"),
        do: Map.put(json, "phone", %{mobile: attrs["phone"]}),
        else: json
    end)
    |> put_contact(attrs, "primary_emergency_contact", "primaryEmergencyContact")
    |> put_contact(attrs, "secondary_emergency_contact", "secondaryEmergencyContact")
  end

  # D4H merges the contact it gets with the one it has, so a cleared field goes as "".
  defp put_contact(json, attrs, name, d4h_name) do
    case attrs[name] do
      %{} = contact ->
        fields = D4H.MemberDetails.contact_fields()
        Map.put(json, d4h_name, Map.new(fields, fn {k, d4h_k} -> {d4h_k, contact[k] || ""} end))

      nil ->
        json
    end
  end

  defp rename(attrs, fields) do
    for {name, d4h_name} <- fields, Map.has_key?(attrs, name), into: %{} do
      {d4h_name, attrs[name]}
    end
  end

  # `payload` is a JSON map, `{:body, bytes}` for a file, or nil for none.
  defp write(context, method, url, payload, build) do
    options = [method: method, url: url, retry: false] ++ payload_options(payload)

    case Req.request(context, options) do
      {:ok, %{status: status} = response} when status in 200..299 -> {:ok, build.(response.body)}
      result -> {:error, write_error(result)}
    end
  end

  defp payload_options(nil), do: []

  defp payload_options({:body, bytes}),
    do: [body: bytes, headers: %{"content-type" => "application/octet-stream"}]

  defp payload_options(json), do: [json: json]

  defp iso(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
