defmodule App.ViewData.ActivityMembers do
  @moduledoc """
  The Members table on an activity's page (#444): every member it invites, by D4H
  status, signed up first, then can't make it, then no reply, each by name. Before the
  start the statuses are replies; from it, D4H's attendance.
  """
  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Repo

  @statuses ["attending", "absent", "requested"]

  @doc "D4H's statuses the table shows, in its order."
  def statuses, do: @statuses

  @doc """
  The activity's invited members' rows, with the member, in the table's order: one per
  member, as `Attendance.one_per_member/1` picks.
  """
  def load(%Activity{} = activity) do
    Attendance
    |> join(:inner, [r], m in assoc(r, :member))
    |> where([r, m], r.activity_id == ^activity.id and m.team_id == ^activity.team_id)
    |> preload([r, m], member: m)
    |> Repo.all()
    |> Attendance.one_per_member()
    |> Enum.filter(&(&1.status in @statuses))
    |> sort()
  end

  @doc "By status in the table's order, then by name."
  def sort(rows) do
    Enum.sort_by(rows, fn row ->
      {Enum.find_index(@statuses, &(&1 == row.status)), String.downcase(row.member.name)}
    end)
  end

  @doc ~s(How many rows have each status, as `%{attending: n, absent: n, requested: n}`.)
  def counts(rows) do
    Map.new(@statuses, fn status ->
      {String.to_existing_atom(status), Enum.count(rows, &(&1.status == status))}
    end)
  end

  @doc "The rows with `status`, or all of them for nil."
  def only(rows, nil), do: rows
  def only(rows, status), do: Enum.filter(rows, &(&1.status == status))

  @doc "Whether a reply came in the 24 hours before `now`: it gets a New tag."
  def new?(%{replied_at: nil}, _now), do: false
  def new?(%{replied_at: replied_at}, now), do: DateTime.diff(now, replied_at) < 24 * 60 * 60

  @doc """
  Whether a row starts on the activity's own day in `timezone`, so its Start shows the
  time alone.
  """
  def same_day?(row_start, activity_start, timezone) do
    local_date(row_start, timezone) == local_date(activity_start, timezone)
  end

  defp local_date(datetime, timezone),
    do: datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
end
