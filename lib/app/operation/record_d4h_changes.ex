defmodule App.Operation.RecordD4HChanges do
  import Ecto.Query

  alias App.Model.ChangeSetRow
  alias App.Model.D4HChange
  alias App.Model.Group
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Repo

  # Keeps what each D4H refresh and sync changed in the local copy as `d4h_changes`, the
  # history on member and activity pages (#174, step 3). The upsert stages call record/4
  # and removed/3 as they write. They only record inside recording/3, which the full
  # refresh and the sync wrap around their run. It lives in the process dictionary so
  # the stages, shared by both runs and called from many places, don't each pass it on.
  # Writes run in the caller's process; only D4H fetches run in tasks.

  @key {__MODULE__, :run}

  # Fields compared per kind. Anything else D4H sends, such as `updatedAt`, is noise.
  @tracked %{
    member: ~w(name position d4h_status d4h_permission joined_at left_at)a,
    activity: ~w(title started_at finished_at is_published tags deleted_at)a,
    attendance: ~w(status started_at finished_at duration_in_minutes)a,
    award: ~w(starts_at ends_at)a,
    group_membership: []
  }

  # Named in `fields` when they change, but their values are never kept.
  @contact_fields ~w(email phone address)a

  @doc """
  Runs `fun` with recording on for `team`. A team's first full refresh records nothing:
  it copies the whole team, and that is the baseline, not a change.
  """
  def recording(%Team{} = team, now, fun) do
    if team.d4h_refreshed_at do
      Process.put(@key, %{
        team_id: team.id,
        seen_after: team.d4h_synced_at || team.d4h_refreshed_at,
        seen_at: now
      })
    end

    try do
      fun.()
    after
      Process.delete(@key)
    end
  end

  @doc """
  What changed between `old` and `new`, two versions of one record, either nil. Returns
  nil when nothing tracked changed, else the action, the changed fields, and the old and
  new values of those fields with string keys. Contact details appear in `fields` only.
  """
  def diff(_kind, nil, nil), do: nil

  def diff(kind, nil, new), do: whole(kind, :added, :new_value, new)
  def diff(kind, old, nil), do: whole(kind, :removed, :old_value, old)

  def diff(kind, old, new) do
    changed = for f <- tracked(kind), Map.get(old, f) != Map.get(new, f), do: f

    if changed == [] do
      nil
    else
      kept = changed -- @contact_fields

      %{
        action: :changed,
        fields: Enum.map(changed, &Atom.to_string/1),
        old_value: values(old, kept),
        new_value: values(new, kept)
      }
    end
  end

  defp whole(kind, action, side, record) do
    values = values(record, Map.fetch!(@tracked, kind))
    Map.put(%{action: action, fields: [], old_value: nil, new_value: nil}, side, values)
  end

  defp tracked(:member), do: @tracked.member ++ @contact_fields
  defp tracked(kind), do: Map.fetch!(@tracked, kind)

  defp values(record, fields) do
    Map.new(fields, fn f -> {Atom.to_string(f), json(Map.get(record, f))} end)
  end

  defp json(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp json(value), do: value

  @doc """
  Records the change from `old` to `new`, either nil, when recording is on. `kind` is
  one of `D4HChange`'s record kinds. Returns `new`.
  """
  def record(kind, old, new, opts \\ []) do
    with %{} = run <- Process.get(@key),
         %{} = change <- diff(kind, old, new),
         record = new || old,
         false <- own_write?(run, kind, change, record) do
      run
      |> build(kind, change, record, opts)
      |> D4HChange.insert!()
    end

    new
  end

  @doc "Records each of `records` as removed, when recording is on."
  def removed(kind, records, opts \\ []) do
    if Process.get(@key), do: Enum.each(records, &record(kind, &1, nil, opts))
    :ok
  end

  defp build(run, kind, change, record, opts) do
    %D4HChange{
      team_id: run.team_id,
      record_kind: kind,
      action: change.action,
      fields: change.fields,
      old_value: change.old_value,
      new_value: change.new_value,
      seen_after: run.seen_after,
      seen_at: run.seen_at,
      member_id: member_id(kind, record),
      activity_id: activity_id(kind, record),
      qualification_id: Map.get(record, :qualification_id),
      group_id: Map.get(record, :group_id),
      d4h_record_id: d4h_id(kind, record),
      label: opts[:label] || label(kind, record)
    }
  end

  defp member_id(:member, record), do: record.id
  defp member_id(:activity, _record), do: nil
  defp member_id(_kind, record), do: record.member_id

  defp activity_id(:activity, record), do: record.id
  defp activity_id(:attendance, record), do: record.activity_id
  defp activity_id(_kind, _record), do: nil

  defp d4h_id(:member, r), do: r.d4h_member_id
  defp d4h_id(:activity, r), do: r.d4h_activity_id
  defp d4h_id(:attendance, r), do: r.d4h_attendance_id
  defp d4h_id(:award, r), do: r.d4h_award_id
  defp d4h_id(:group_membership, r), do: r.d4h_group_membership_id

  # Qualifications and groups can be deleted by a later refresh, so their name is kept.
  defp label(:award, %{qualification_id: id}) when is_integer(id),
    do: Qualification |> where(id: ^id) |> select([q], q.title) |> Repo.one()

  defp label(:group_membership, %{group_id: id}) when is_integer(id),
    do: Group |> where(id: ^id) |> select([g], g.title) |> Repo.one()

  defp label(_kind, _record), do: nil

  # SAR Duty's own writes reach the copy on the next sync, like anyone's. They're on the
  # page already from their change set, so a change that matches a row applied in the
  # last day isn't recorded twice. Group rules update the copy as they write, so their
  # changes never show up here.
  defp own_write?(run, :attendance, %{action: action}, record)
       when action in [:added, :changed] do
    since = DateTime.add(run.seen_at, -1, :day)

    ChangeSetRow
    |> where([r], r.team_id == ^run.team_id and r.status == :applied)
    |> where([r], r.d4h_record_id == ^record.d4h_attendance_id and r.applied_at >= ^since)
    |> select([r], r.new_value)
    |> Repo.all()
    |> Enum.any?(&(&1["status"] == record.status))
  end

  defp own_write?(_run, _kind, _change, _record), do: false
end
