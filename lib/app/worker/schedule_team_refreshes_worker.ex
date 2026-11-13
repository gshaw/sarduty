defmodule App.Worker.ScheduleTeamRefreshesWorker do
  @moduledoc """
  The full refresh. Every 10 minutes it queues a refresh for each team that hasn't had
  one since 06:00 UTC, and tells Healthchecks whether any team is still waiting 2 hours
  later. Nothing carries over from one run to the next, so a crashed job, a deploy over
  06:00, or D4H down for the morning heals on its own once the cause is gone, rather
  than waiting a day. See docs/d4h-sync.md.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias App.Adapter.Healthchecks
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.RefreshTeamDataWorker

  # Teams come due at 06:00 UTC, 23:00 in Vancouver. One still due 2 hours later pages.
  @due_time ~T[06:00:00]
  @grace_hours 2

  @doc "Queues a refresh of every D4H team now: Adminland's button."
  def enqueue_all, do: Enum.each(teams(), &RefreshTeamDataWorker.enqueue/1)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    plan = plan(DateTime.utc_now())
    Enum.each(plan.queue, &RefreshTeamDataWorker.enqueue/1)
    Healthchecks.ping(:refresh, if(plan.overdue == [], do: :success, else: :fail))
    :ok
  end

  @doc "plan/3 for every D4H team, as the database stands at `now`."
  def plan(now), do: plan(teams(), held(due_since(now)), now)

  # Not the sync's teams: a team whose key D4H rejected still gets its one try a day,
  # which clears the mark when the key works again. A demo needs no refresh: its sync
  # keeps it, and it lives 3 days (#857).
  defp teams, do: Enum.filter(Team.get_all_real(), & &1.d4h_team_id)

  @doc """
  Pure. `teams` are on D4H. `held` has the ids of teams whose refresh is
  `retrying` after a failure, and of those `cancelled` since the last 06:00 for a key only
  a person can fix. Returns the count of `teams`, the teams `due` (no refresh since the
  last 06:00, and not cancelled), the due ones to `queue` (not retrying already), and the
  due ones `overdue` once the grace is past.
  """
  def plan(teams, %{retrying: retrying, cancelled: cancelled}, now) do
    since = due_since(now)
    due = Enum.filter(teams, &(due?(&1, since) and &1.id not in cancelled))
    late? = DateTime.compare(now, DateTime.add(since, @grace_hours, :hour)) != :lt

    %{
      teams: length(teams),
      due: due,
      queue: Enum.reject(due, &(&1.id in retrying)),
      overdue: if(late?, do: due, else: [])
    }
  end

  @doc "Pure. The last 06:00 UTC at or before `now`: a team refreshed since is up to date."
  def due_since(now) do
    today = now |> DateTime.to_date() |> DateTime.new!(@due_time, "Etc/UTC")
    if DateTime.compare(now, today) == :lt, do: DateTime.add(today, -1, :day), else: today
  end

  defp due?(%Team{d4h_refreshed_at: nil}, _since), do: true
  defp due?(%Team{d4h_refreshed_at: at}, since), do: DateTime.compare(at, since) == :lt

  # Oban's own retries pace a failing team, so the next run doesn't queue a second one
  # beside it. A cancelled job had a missing or rejected key.
  defp held(since) do
    rows =
      Oban.Job
      |> where([j], j.worker == ^inspect(RefreshTeamDataWorker))
      |> where(
        [j],
        j.state == "retryable" or (j.state == "cancelled" and j.cancelled_at >= ^since)
      )
      |> select([j], {j.state, fragment("json_extract(?, '$.team_id')", j.args)})
      |> Repo.all()

    %{
      retrying: for({"retryable", id} <- rows, do: id),
      cancelled: for({"cancelled", id} <- rows, do: id)
    }
  end
end
