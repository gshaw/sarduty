defmodule App.Operation.RecordAttendanceScan do
  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.AttendanceScan
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Repo

  # Records a member arriving or leaving from the door's page. `kind` is "arrived" or
  # "left", and `override` is the "HH:MM" typed at the door, or "" for the moment of the
  # scan. Each returns `{:ok, scan}` with the member, or `{:error, reason}`.

  @doc """
  From what the camera read on an ID card, or a code typed from one. `hosts` are the
  sites a card's QR code may link to.
  """
  def from_card(%AttendanceLink{} = link, input, hosts, kind, override, now) do
    with :ok <- check_open(link, now),
         {:ok, card} <- find_card(input, hosts),
         :ok <- check_card(link, card, now) do
      record(link, card.member, kind, "card", override, now)
    end
  end

  @doc "From a member picked by name, for someone without their ID card."
  def from_name(%AttendanceLink{} = link, member_id, kind, override, now) do
    with :ok <- check_open(link, now),
         %Member{} = member <- Repo.get_by(Member, id: member_id, team_id: link.team_id) do
      record(link, member, kind, "name", override, now)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc "Removes one of the link's activity's scans, while the link is open."
  def undo(%AttendanceLink{} = link, scan_id, now) do
    with :ok <- check_open(link, now) do
      AttendanceScan.delete(link.activity, scan_id)
      :ok
    end
  end

  defp check_open(link, now),
    do: if(AttendanceLink.open?(link, now), do: :ok, else: {:error, :closed})

  defp find_card(input, hosts) do
    case MemberCard.code_from_scan(input, hosts) do
      code when is_binary(code) ->
        case MemberCard.find_by_code(code) do
          %MemberCard{} = card -> {:ok, card}
          nil -> {:error, :not_found}
        end

      {:other_site, _host} ->
        {:error, :other_site}

      nil ->
        {:error, :not_found}
    end
  end

  defp check_card(link, card, now) do
    if card.team_id == link.team_id and card.member.team_id == link.team_id do
      case MemberCard.status(card, now) do
        :active -> :ok
        :inactive -> {:error, :left_team}
        :revoked -> {:error, :revoked}
      end
    else
      {:error, :other_team}
    end
  end

  defp record(link, member, kind, method, override, now) do
    timezone = link.activity.team.timezone

    case override_at(override, link.activity, now, timezone) do
      {:ok, override_at} ->
        scan =
          AttendanceScan.insert!(%AttendanceScan{
            team_id: link.team_id,
            activity_id: link.activity_id,
            member_id: member.id,
            attendance_link_id: link.id,
            kind: kind,
            method: method,
            scanned_at: now,
            override_at: override_at
          })

        {:ok, %{scan | member: member}}

      :error ->
        {:error, :bad_time}
    end
  end

  @doc """
  The time typed at the door, "HH:MM" in the team's time zone, as UTC. It goes on the
  date that puts it nearest the activity, so a catch-up the next morning lands on the
  activity's day, and a time after midnight lands on the right side of it. Between
  dates equally near, as on a multi-day activity, the one nearest `now` wins. `{:ok, nil}`
  when nothing was typed, and `:error` when it isn't a time.
  """
  def override_at(text, %Activity{} = activity, now, timezone) do
    case String.trim(text || "") do
      "" ->
        {:ok, nil}

      text ->
        case parse_time(text) do
          {:ok, time} -> {:ok, nearest(time, activity, now, timezone)}
          _ -> :error
        end
    end
  end

  defp nearest(time, activity, now, timezone) do
    first = activity.started_at |> local_date(timezone) |> Date.add(-1)
    last = activity.finished_at |> local_date(timezone) |> Date.add(1)
    dates = Date.range(first, last)

    dates
    |> Enum.map(&on_date(&1, time, timezone))
    |> Enum.min_by(&{distance(&1, activity), abs(DateTime.diff(&1, now))})
  end

  defp local_date(datetime, timezone),
    do: datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

  defp on_date(date, time, timezone) do
    case DateTime.new(date, time, timezone) do
      {:ok, local} -> to_utc(local)
      # A time skipped by a daylight saving change, or one that happens twice.
      {:gap, _before, after_gap} -> to_utc(after_gap)
      {:ambiguous, first, _second} -> to_utc(first)
    end
  end

  # Seconds from the activity's start-to-end window, 0 inside it.
  defp distance(at, %Activity{started_at: started_at, finished_at: finished_at}) do
    cond do
      DateTime.before?(at, started_at) -> DateTime.diff(started_at, at)
      DateTime.after?(at, finished_at) -> DateTime.diff(at, finished_at)
      true -> 0
    end
  end

  # Stored to the microsecond, like the moment of a scan.
  defp to_utc(local), do: %{DateTime.shift_zone!(local, "Etc/UTC") | microsecond: {0, 6}}

  defp parse_time(text) do
    case Regex.run(~r/^(\d{1,2}):?(\d{2})$/, text) do
      [_, hours, minutes] ->
        [hours, minutes]
        |> Enum.map(&String.to_integer/1)
        |> then(fn [h, m] -> Time.new(h, m, 0) end)

      nil ->
        :error
    end
  end
end
