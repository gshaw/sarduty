defmodule App.Worker.FinishRunWorker do
  @moduledoc """
  Tells Healthchecks when a run of team jobs is over: the sync every 10 minutes, or the
  nightly refresh. The scheduler queues it beside the team jobs, and it waits until none
  are left, so one ping covers every team and a slow run shows as late.

  The refresh fails when any team's job ran out of attempts. A missing or rejected key
  cancels the job instead, so it doesn't count: only the team can fix it, and the
  dashboards already say so. A sync never fails the run, since a failed sync is
  cancelled and the next is 10 minutes away.

  It also records the run as an event: how long it took, how many teams, and what the
  team events since it started say, for the admin events page.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    # One per run kind: a run that overlaps the next shares its ping.
    unique: [keys: [:run], states: [:available, :scheduled, :executing]]

  import Ecto.Query

  alias App.Adapter.Healthchecks
  alias App.Model.Event
  alias App.Repo
  alias App.Worker.RefreshTeamDataWorker
  alias App.Worker.SyncTeamChangesWorker

  @runs %{
    "sync" => %{
      check: :sync,
      worker: SyncTeamChangesWorker,
      wait: 5,
      event: :d4h_sync_round,
      team_event: :d4h_team_sync
    },
    "refresh" => %{
      check: :refresh,
      worker: RefreshTeamDataWorker,
      wait: 60,
      event: :d4h_refresh_run,
      team_event: :d4h_team_refresh
    }
  }

  # A job in any of these will still run, now or after a retry. Only jobs queued since the
  # run started count, so one orphaned long ago can't hold every run open.
  @pending ~w(available scheduled executing retryable)

  @doc "Pings the start of a run of `teams` jobs and queues the job that pings its end."
  def start(run, teams, now) when is_map_key(@runs, run) do
    Healthchecks.ping(@runs[run].check, :start)
    %{run: run, teams: teams, started_at: now} |> new() |> Oban.insert!()
  end

  @doc "`:wait` while jobs are left, then `:fail` if any ran out of attempts, else `:success`."
  def outcome(pending, discarded) when pending > 0 and discarded >= 0, do: :wait
  def outcome(0, 0), do: :success
  def outcome(0, _discarded), do: :fail

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run" => run, "started_at" => started_at} = args}) do
    %{check: check, worker: worker, wait: wait} = config = Map.fetch!(@runs, run)
    {:ok, started_at, 0} = DateTime.from_iso8601(started_at)
    jobs = jobs(worker, started_at)
    pending = jobs |> where([j], j.state in @pending) |> Repo.aggregate(:count)

    discarded =
      jobs
      |> where([j], j.state == "discarded" and j.discarded_at >= ^started_at)
      |> Repo.aggregate(:count)

    case outcome(pending, discarded) do
      :wait ->
        {:snooze, wait}

      signal ->
        Healthchecks.ping(check, signal)
        record(config, args["teams"], started_at, signal)
        :ok
    end
  end

  defp record(config, teams, started_at, signal) do
    now = DateTime.utc_now()
    count = &Event.count_since(config.team_event, started_at, %{outcome: &1})

    Event.record!(config.event,
      duration_ms: Event.duration_ms(started_at, now),
      occurred_at: now,
      data: %{
        outcome: Atom.to_string(signal),
        teams: teams,
        changed: count.("changed"),
        failed: count.("failed"),
        key_rejected: count.("key_rejected") + count.("key_error"),
        rate_limited: Event.count_since(:d4h_rate_limited, started_at)
      }
    )
  end

  # Oban stores inserted_at to the second, after the run's start was read.
  defp jobs(worker, started_at) do
    since = DateTime.truncate(started_at, :second)
    where(Oban.Job, [j], j.worker == ^inspect(worker) and j.inserted_at >= ^since)
  end
end
