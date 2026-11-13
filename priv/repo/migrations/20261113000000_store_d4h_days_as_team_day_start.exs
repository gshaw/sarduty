defmodule App.Repo.Migrations.StoreD4HDaysAsTeamDayStart do
  use Ecto.Migration

  # D4H keeps a member's join and leave dates and an award's start and end as the day at
  # 00:00 UTC, which reads as the day before on a Canadian clock (#1058). The copy now
  # keeps each as the start of that day on the team's clock, as the refresh writes it.
  # A value at 00:00 UTC is D4H's day; any other, such as a leave date the refresh
  # stamped when a member vanished, becomes the start of its day on the team's clock.
  # The history keeps D4H's values too, so its rows move the same way, but only values
  # at 00:00 UTC: an exact time there already reads as the right day.

  @member_fields ~w(joined_at left_at)
  @award_fields ~w(starts_at ends_at)

  def up, do: rewrite(&to_day_start/2, &history_up/2)
  def down, do: rewrite(&to_d4h_day/2, &history_down/2)

  defp rewrite(convert, history) do
    # Time zones come from Tzdata, which a migration run outside the app hasn't started.
    {:ok, _apps} = Application.ensure_all_started(:tzdata)

    zones = Map.new(repo().query!("SELECT id, timezone FROM teams").rows, &List.to_tuple/1)

    rewrite_table(
      "SELECT m.id, m.team_id, m.joined_at, m.left_at FROM members m",
      "members",
      @member_fields,
      zones,
      convert
    )

    rewrite_table(
      """
      SELECT a.id, m.team_id, a.starts_at, a.ends_at
      FROM member_qualification_awards a JOIN members m ON m.id = a.member_id
      """,
      "member_qualification_awards",
      @award_fields,
      zones,
      convert
    )

    rewrite_json(
      "SELECT id, team_id, record_kind, old_value, new_value FROM d4h_changes",
      "d4h_changes",
      zones,
      history
    )

    rewrite_json(
      "SELECT id, team_id, action, old_value, new_value FROM change_set_rows",
      "change_set_rows",
      zones,
      history
    )
  end

  defp rewrite_table(select, table, fields, zones, convert) do
    for [id, team_id | values] <- repo().query!(select).rows,
        zone = zones[team_id],
        zone != nil do
      new_values = Enum.map(values, &move(&1, zone, convert))

      if new_values != values do
        sets = Enum.map_join(fields, ", ", &"#{&1} = ?")
        repo().query!("UPDATE #{table} SET #{sets} WHERE id = ?", new_values ++ [id])
      end
    end
  end

  defp move(nil, _zone, _convert), do: nil

  defp move(value, zone, convert) do
    datetime = parse(value)
    moved = convert.(datetime, zone)
    if moved == datetime, do: value, else: text(moved)
  end

  # The day fields in a history row's values: members' and awards' only.
  defp day_keys(kind) when kind in ~w(member create_member update_member retire_member),
    do: @member_fields

  defp day_keys(kind) when kind in ~w(award award_qualification attach_award_document),
    do: @award_fields

  defp day_keys(_kind), do: []

  defp rewrite_json(select, table, zones, history) do
    for [id, team_id, kind, old_value, new_value] <- repo().query!(select).rows,
        zone = zones[team_id],
        zone != nil,
        keys = day_keys(kind),
        keys != [] do
      new_old = json(old_value, keys, zone, history)
      new_new = json(new_value, keys, zone, history)

      if {new_old, new_new} != {old_value, new_value} do
        repo().query!(
          "UPDATE #{table} SET old_value = ?, new_value = ? WHERE id = ?",
          [new_old, new_new, id]
        )
      end
    end
  end

  defp json(nil, _keys, _zone, _history), do: nil

  defp json(text, keys, zone, history) do
    map = Jason.decode!(text)

    changed =
      Enum.reduce(keys, map, fn key, acc ->
        case acc do
          %{^key => value} when is_binary(value) ->
            datetime = parse(value)
            moved = history.(datetime, zone)
            if moved == datetime, do: acc, else: Map.put(acc, key, text(moved))

          _ ->
            acc
        end
      end)

    if changed == map, do: text, else: Jason.encode!(changed)
  end

  defp history_up(datetime, zone),
    do: if(midnight_utc?(datetime), do: to_day_start(datetime, zone), else: datetime)

  defp history_down(datetime, zone), do: to_d4h_day(datetime, zone)

  defp to_day_start(datetime, zone) do
    date =
      if midnight_utc?(datetime),
        do: DateTime.to_date(datetime),
        else: datetime |> DateTime.shift_zone!(zone) |> DateTime.to_date()

    day_start(date, zone)
  end

  # Back to D4H's day at 00:00 UTC. Only a value at the start of its day moves.
  defp to_d4h_day(datetime, zone) do
    date = datetime |> DateTime.shift_zone!(zone) |> DateTime.to_date()

    if day_start(date, zone) == datetime,
      do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC"),
      else: datetime
  end

  defp midnight_utc?(datetime), do: DateTime.to_time(datetime) == ~T[00:00:00]

  defp day_start(date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, datetime} -> DateTime.shift_zone!(datetime, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
    end
  end

  defp parse(text) do
    case DateTime.from_iso8601(text) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _} -> text |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")
    end
  end

  defp text(datetime), do: DateTime.to_iso8601(datetime)
end
