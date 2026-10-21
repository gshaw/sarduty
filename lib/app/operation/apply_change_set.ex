defmodule App.Operation.ApplyChangeSet do
  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Team
  alias App.Repo

  # The one place SAR Duty writes to D4H (#174). A test fails if any other module calls
  # D4H's write functions. Before writing it reads D4H fresh, and a row whose D4H record
  # changed since it was proposed is skipped rather than overwritten. Each row records
  # D4H's answer. Writes don't retry; a failed row stays failed and applying the set
  # again tries it once more.

  # Writes for a team on SAR Duty Records (docs/records.md), from App.Operation.ApplyEdit.
  # Each changes the record its row names; nothing is read first.
  @edits [
    :create_member,
    :update_member,
    :retire_member,
    :rejoin_member,
    :set_member_photo,
    :remove_member_photo,
    :create_activity,
    :update_activity,
    :delete_activity,
    :create_qualification,
    :update_qualification,
    :delete_qualification,
    :award_qualification,
    :remove_award,
    :create_group,
    :update_group,
    :delete_group,
    :create_equipment_item,
    :update_equipment_item,
    :delete_equipment_item
  ]

  @doc """
  Applies the set's proposed and failed rows. `{:ok, rows}` with each row as recorded;
  `{:error, :no_team_key}`, `{:error, :deleted}` or `{:error, :published}` for an
  activity that can't change, or `{:error, %D4H.Error{}}` when D4H can't be read.

  `user` is who applies it, or nil for SAR Duty itself, as for the nightly chore send.

  `photo:` in `opts` is the image a `:set_member_photo` row sends. The row never holds
  it, so a photo is never kept in SAR Duty.
  """
  def call(team, change_set, user, now, opts \\ [])

  def call(%Team{} = team, %ChangeSet{team_id: team_id} = change_set, user, now, opts)
      when team_id == team.id and (is_struct(user, User) or is_nil(user)) do
    change_set = Repo.preload(change_set, [:activity, :rows])

    with :ok <- check_team(team),
         d4h = D4H.build_context_from_team(team),
         {:ok, current} <- read_current(d4h, change_set) do
      # Rows go in order, so one can use the activity an earlier row created (#341).
      {rows, _created} =
        change_set.rows
        |> Enum.filter(&(&1.status in [:proposed, :failed]))
        |> Enum.map_reduce(created_activity(change_set.rows), fn row, created ->
          row = with_created(row, created)
          recorded = ChangeSetRow.record!(row, apply_row(d4h, row, current, opts), now)
          {recorded, created_now(recorded) || created}
        end)

      ChangeSet.mark_applied!(change_set, user, now)
      {:ok, rows}
    end
  end

  # An activity the set created on an earlier apply, for its rows that failed then.
  defp created_activity(rows), do: Enum.find_value(rows, &created_now/1)

  defp created_now(%ChangeSetRow{action: :create_activity, status: :applied} = row),
    do: row.d4h_record_id

  defp created_now(_row), do: nil

  defp with_created(row, created) do
    if ChangeSetRow.created_in_set?(row) and created,
      do: ChangeSetRow.fill_activity!(row, created),
      else: row
  end

  defp check_team(%Team{d4h_access_key: nil}), do: {:error, :no_team_key}
  defp check_team(%Team{}), do: :ok

  # SAR Duty owns a chore event and rebuilds it on each send (#341), so D4H is not read
  # for conflicts: the set read the event's attendance as it was planned, for ids.
  defp read_current(_d4h, %ChangeSet{source: :chores}), do: {:ok, :owned}

  # An attendance set reads the activity's rows now, and D4H's published flag, since
  # attendance on a published activity is locked.
  defp read_current(_d4h, %ChangeSet{activity: nil}), do: {:ok, nil}

  defp read_current(_d4h, %ChangeSet{activity: %{deleted_at: %DateTime{}}}),
    do: {:error, :deleted}

  # An edit changes the record its row names, whatever D4H holds now.
  defp read_current(_d4h, %ChangeSet{source: :edit}), do: {:ok, nil}

  # An equipment set reads the activity's usages now. D4H takes equipment on a published
  # activity, so the published flag doesn't matter.
  defp read_current(d4h, %ChangeSet{source: :equipment, activity: activity}),
    do: D4H.fetch_activity_equipment_usages(d4h, activity.d4h_activity_id)

  # A tags set reads the activity's tags now, so a change made in D4H since the page
  # opened isn't overwritten. D4H takes tags on a published activity.
  defp read_current(d4h, %ChangeSet{source: :tags, activity: activity}) do
    with {:ok, ids} <-
           D4H.fetch_activity_tag_ids(d4h, activity.d4h_activity_id, activity.activity_kind) do
      {:ok, {:tags, ids |> Enum.uniq() |> Enum.sort()}}
    end
  end

  defp read_current(d4h, %ChangeSet{activity: activity}) do
    case D4H.fetch_activity_published(d4h, activity.d4h_activity_id, activity.activity_kind) do
      {:ok, false} -> D4H.fetch_attendance_infos(d4h, activity.d4h_activity_id)
      {:ok, true} -> {:error, :published}
      error -> error
    end
  end

  defp apply_row(d4h, row, current, opts) do
    case check(row, current) do
      :ok -> write(d4h, row, opts)
      skip -> skip
    end
  end

  defp write(d4h, %ChangeSetRow{action: :set_member_photo} = row, opts) do
    case opts[:photo] do
      nil ->
        {:failed, "Upload the photo again."}

      bytes ->
        d4h |> D4H.set_member_photo(row.d4h_record_id, bytes) |> record_result(& &1.d4h_member_id)
    end
  end

  defp write(d4h, row, _opts), do: write(d4h, row)

  @doc """
  Whether a row can still be written, given D4H's attendance rows `current` (nil for a
  group set). `:ok`, or `{:skipped, text}` when D4H changed the record first.
  """
  def check(%ChangeSetRow{} = row, :owned) do
    if ChangeSetRow.created_in_set?(row) and is_nil(row.new_value["d4h_activity_id"]),
      do: {:failed, "The event was not added to D4H, so this was not sent."},
      else: :ok
  end

  def check(%ChangeSetRow{action: :update_attendance} = row, current) do
    case Enum.find(current, &(&1.d4h_attendance_id == row.d4h_record_id)) do
      nil ->
        {:skipped, "The attendance row is gone from D4H. Review again."}

      info ->
        if info.status == row.old_value["status"],
          do: :ok,
          else: {:skipped, "D4H changed this since the review. Review again."}
    end
  end

  def check(%ChangeSetRow{action: :create_attendance} = row, current) do
    if Enum.any?(current, &(&1.d4h_member_id == row.new_value["d4h_member_id"])),
      do: {:skipped, "D4H has attendance for this member now. Review again."},
      else: :ok
  end

  def check(%ChangeSetRow{action: action}, nil)
      when action in [:add_group_member, :remove_group_member],
      do: :ok

  # D4H would take a second usage of the same item and count it twice.
  def check(%ChangeSetRow{action: :create_equipment_usage} = row, current) do
    if Enum.any?(current, &(&1.d4h_equipment_id == row.new_value["d4h_equipment_id"])),
      do: {:skipped, "D4H has this item on the activity now."},
      else: :ok
  end

  def check(%ChangeSetRow{action: :delete_equipment_usage} = row, current) do
    if Enum.any?(current, &(&1.d4h_equipment_usage_id == row.d4h_record_id)),
      do: :ok,
      else: {:skipped, "D4H no longer has this item on the activity."}
  end

  def check(%ChangeSetRow{action: action}, nil) when action in @edits, do: :ok

  def check(%ChangeSetRow{action: :set_activity_tags} = row, {:tags, ids}) do
    if ids == row.old_value["tag_ids"],
      do: :ok,
      else: {:skipped, "The tags changed in D4H since the page opened. Open it again."}
  end

  # An equipment set's tag row was read from D4H as the set was planned, a moment before.
  def check(%ChangeSetRow{action: :set_activity_tags}, _current), do: :ok

  defp write(d4h, %ChangeSetRow{action: :update_attendance, new_value: new_value} = row) do
    d4h
    |> D4H.set_attendance(
      row.d4h_record_id,
      new_value["status"],
      time(new_value["starts_at"]),
      time(new_value["ends_at"])
    )
    |> attendance_result()
  end

  defp write(d4h, %ChangeSetRow{action: :create_attendance, new_value: new_value}) do
    d4h
    |> D4H.create_attendance(
      new_value["d4h_activity_id"],
      new_value["d4h_member_id"],
      time(new_value["starts_at"]),
      time(new_value["ends_at"]),
      new_value["status"] || "ATTENDING"
    )
    |> attendance_result()
  end

  defp write(d4h, %ChangeSetRow{action: :delete_attendance} = row) do
    case D4H.delete_attendance(d4h, row.d4h_record_id) do
      :ok -> {:applied, row.d4h_record_id}
      {:error, error} -> {:failed, attendance_failure_text(error)}
    end
  end

  defp write(d4h, %ChangeSetRow{action: :publish_activity} = row) do
    case D4H.publish_activity(
           d4h,
           row.old_value["kind"],
           row.d4h_record_id,
           row.new_value["published"]
         ) do
      {:ok, id} -> {:applied, id}
      {:error, error} -> {:failed, Exception.message(error)}
    end
  end

  defp write(d4h, %ChangeSetRow{action: :add_group_member, new_value: new_value}) do
    case D4H.add_group_member(d4h, new_value["d4h_group_id"], new_value["d4h_member_id"]) do
      {:ok, membership} -> {:applied, membership.d4h_group_membership_id}
      {:error, error} -> {:failed, Exception.message(error)}
    end
  end

  defp write(d4h, %ChangeSetRow{action: :remove_group_member} = row) do
    case D4H.remove_group_membership(d4h, row.d4h_record_id) do
      :ok -> {:applied, row.d4h_record_id}
      {:error, error} -> {:failed, Exception.message(error)}
    end
  end

  defp write(d4h, %ChangeSetRow{action: :create_equipment_usage, new_value: new_value}) do
    case D4H.create_equipment_usage(
           d4h,
           new_value["d4h_activity_id"],
           new_value["d4h_equipment_id"],
           new_value["minutes"],
           new_value["km"]
         ) do
      {:ok, usage} -> {:applied, usage.d4h_equipment_usage_id}
      {:error, error} -> {:failed, Exception.message(error)}
    end
  end

  defp write(d4h, %ChangeSetRow{action: :delete_equipment_usage} = row) do
    case D4H.delete_equipment_usage(d4h, row.d4h_record_id) do
      :ok -> {:applied, row.d4h_record_id}
      {:error, error} -> {:failed, Exception.message(error)}
    end
  end

  defp write(d4h, %ChangeSetRow{action: :set_activity_tags} = row) do
    kind = row.old_value["kind"]

    case D4H.set_activity_tags(d4h, kind, row.d4h_record_id, row.new_value["tag_ids"]) do
      {:ok, _activity} -> {:applied, row.d4h_record_id}
      {:error, error} -> {:failed, Exception.message(error)}
    end
  end

  defp write(d4h, %ChangeSetRow{action: :create_member, new_value: new_value}),
    do: d4h |> D4H.create_member(new_value) |> record_result(& &1.d4h_member_id)

  defp write(d4h, %ChangeSetRow{action: :update_member} = row),
    do:
      d4h
      |> D4H.update_member(row.d4h_record_id, row.new_value)
      |> record_result(& &1.d4h_member_id)

  defp write(d4h, %ChangeSetRow{action: :retire_member} = row),
    do:
      d4h
      |> D4H.retire_member(row.d4h_record_id, row.new_value["left_at"])
      |> record_result(& &1.d4h_member_id)

  defp write(d4h, %ChangeSetRow{action: :rejoin_member} = row),
    do: d4h |> D4H.rejoin_member(row.d4h_record_id) |> record_result(& &1.d4h_member_id)

  defp write(d4h, %ChangeSetRow{action: :remove_member_photo} = row),
    do: d4h |> D4H.remove_member_photo(row.d4h_record_id) |> record_result(& &1.d4h_member_id)

  # An activity's kind is in a create's new_value, and in the old_value of a change.
  defp write(d4h, %ChangeSetRow{action: :create_activity, new_value: new_value}) do
    d4h
    |> D4H.create_activity(new_value["kind"], Map.delete(new_value, "kind"))
    |> record_result(& &1.d4h_activity_id)
  end

  defp write(d4h, %ChangeSetRow{action: :update_activity} = row) do
    d4h
    |> D4H.update_activity(row.old_value["kind"], row.d4h_record_id, row.new_value)
    |> record_result(& &1.d4h_activity_id)
  end

  defp write(d4h, %ChangeSetRow{action: :delete_activity} = row) do
    d4h
    |> D4H.delete_activity(row.old_value["kind"], row.d4h_record_id)
    |> record_result(& &1)
  end

  defp write(d4h, %ChangeSetRow{action: :create_qualification, new_value: new_value}),
    do:
      d4h
      |> D4H.create_qualification(new_value["title"])
      |> record_result(& &1.d4h_qualification_id)

  defp write(d4h, %ChangeSetRow{action: :update_qualification} = row) do
    d4h
    |> D4H.update_qualification(row.d4h_record_id, row.new_value["title"])
    |> record_result(& &1.d4h_qualification_id)
  end

  defp write(d4h, %ChangeSetRow{action: :delete_qualification} = row),
    do: d4h |> D4H.delete_qualification(row.d4h_record_id) |> record_result(& &1)

  defp write(d4h, %ChangeSetRow{action: :award_qualification, new_value: new_value}) do
    d4h
    |> D4H.award_qualification(
      new_value["d4h_qualification_id"],
      new_value["d4h_member_id"],
      new_value["starts_at"],
      new_value["ends_at"]
    )
    |> record_result(& &1.d4h_award_id)
  end

  defp write(d4h, %ChangeSetRow{action: :remove_award} = row),
    do: d4h |> D4H.remove_award(row.d4h_record_id) |> record_result(& &1)

  defp write(d4h, %ChangeSetRow{action: :create_group, new_value: new_value}),
    do: d4h |> D4H.create_group(new_value["title"]) |> record_result(& &1.d4h_group_id)

  defp write(d4h, %ChangeSetRow{action: :update_group} = row),
    do:
      d4h
      |> D4H.update_group(row.d4h_record_id, row.new_value["title"])
      |> record_result(& &1.d4h_group_id)

  defp write(d4h, %ChangeSetRow{action: :delete_group} = row),
    do: d4h |> D4H.delete_group(row.d4h_record_id) |> record_result(& &1)

  defp write(d4h, %ChangeSetRow{action: :create_equipment_item, new_value: new_value}),
    do:
      d4h
      |> D4H.create_equipment_item(new_value)
      |> record_result(& &1.d4h_equipment_id)

  defp write(d4h, %ChangeSetRow{action: :update_equipment_item} = row) do
    d4h
    |> D4H.update_equipment_item(row.d4h_record_id, row.new_value)
    |> record_result(& &1.d4h_equipment_id)
  end

  defp write(d4h, %ChangeSetRow{action: :delete_equipment_item} = row),
    do: d4h |> D4H.delete_equipment_item(row.d4h_record_id) |> record_result(& &1)

  defp record_result({:ok, record}, id), do: {:applied, id.(record)}
  defp record_result({:error, error}, _id), do: {:failed, edit_failure_text(error)}

  # Records refuses a write with a title that says what is wrong, so that is the message.
  defp edit_failure_text(%D4H.Error{status: status, message: message}) when status in 400..499,
    do: String.replace(message, ~r/^D4H API error \(\d+\): /, "")

  defp edit_failure_text(_error),
    do: "SAR Duty Records did not answer. Try again in a few minutes."

  defp attendance_result({:ok, info}), do: {:applied, info.d4h_attendance_id}
  defp attendance_result({:error, error}), do: {:failed, attendance_failure_text(error)}

  # D4H answers 400 or 404 when the activity or the attendance row is gone, so that
  # says so before D4H's own text.
  defp attendance_failure_text(%D4H.Error{status: status} = error) when status in [400, 404],
    do: "The activity may have been deleted or changed in D4H. #{Exception.message(error)}"

  defp attendance_failure_text(error), do: Exception.message(error)

  defp time(nil), do: nil

  defp time(iso) do
    {:ok, datetime, 0} = DateTime.from_iso8601(iso)
    datetime
  end

  @doc "A time for a row's `old_value` or `new_value`, which are stored as JSON."
  def iso(nil), do: nil
  def iso(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
