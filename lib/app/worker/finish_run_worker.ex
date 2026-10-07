defmodule App.Worker.FinishRunWorker do
  @moduledoc """
  Tells Healthchecks when a run of team jobs is over: the sync every 10 minutes, or the
  nightly refresh. The scheduler queues it beside the team jobs, and it waits until none
  are left, so one ping covers every team and a slow run shows as late.

  The refresh fails when any team's job ran out of attempts. A missing or rejected key
  cancels the job instead, so it doesn't count: only the team can fix it, and the
  dashboards already say so. A sync never fails the run, since a failed sync is
  cancelled and the next is 10 minutes away.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    # One per run kind: a run that overlaps the next shares its ping.
    unique: [keys: [:run], states: [:available, :scheduled, :executing]]

  import Ecto.Query

  alias App.Adapter.Healthchecks
  alias App.Repo
  alias App.Worker.RefreshTeamDataWorker
  alias App.Worker.SyncTeamChangesWorker

  @runs %{
    "sync" => %{check: :sync, worker: SyncTeamChangesWorker, wait: 5},
    "refresh" => %{check: :refresh, worker: RefreshTeamDataWorker, wait: 60}
  }

  # A job in any of these will still run, now or after a retry.
  @pending ~w(available scheduled executing retryable)

  @doc "Pings the run's start and queues the job that pings its end."
  def start(run, now) when is_map_key(@runs, run) do
    Healthchecks.ping(@runs[run].check, :start)
    %{run: run, started_at: now} |> new() |> Oban.insert!()
  end

  @doc "`:wait` while jobs are left, then `:fail` if any ran out of attempts, else `:success`."
  def outcome(pending, discarded) when pending > 0 and discarded >= 0, do: :wait
  def outcome(0, 0), do: :success
  def outcome(0, _discarded), do: :fail

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run" => run, "started_at" => started_at}}) do
    %{check: check, worker: worker, wait: wait} = Map.fetch!(@runs, run)
    {:ok, started_at, 0} = DateTime.from_iso8601(started_at)
    jobs = jobs(worker)
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
        :ok
    end
  end

  defp jobs(worker), do: where(Oban.Job, worker: ^inspect(worker))
end
