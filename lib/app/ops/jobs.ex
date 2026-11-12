defmodule App.Ops.Jobs do
  @moduledoc """
  Oban jobs by worker and state, for jobs added or tried in the last hour, or
  `--minutes N`. With a worker, `RenewLetterCodes` or `App.Worker.RenewLetterCodesWorker`,
  only that worker's jobs, and the newest error when one failed.
  """

  use App.Ops.Task,
    name: "jobs",
    usage: "jobs [WORKER] [--minutes N]",
    summary: "Oban jobs by worker and state, from the last hour or N minutes."

  import Ecto.Query

  alias App.Repo

  @impl App.Ops.Task
  def run(args) do
    case OptionParser.parse(args, strict: [minutes: :integer]) do
      {opts, workers, []} when length(workers) <= 1 ->
        minutes = Keyword.get(opts, :minutes, 60)

        if minutes > 0,
          do: jobs(List.first(workers), DateTime.add(DateTime.utc_now(), -minutes, :minute)),
          else: usage_error()

      _ ->
        usage_error()
    end
  end

  defp usage_error, do: {:error, "Usage: " <> usage()}

  defp jobs(nil, since) do
    rows =
      since
      |> recent()
      |> group_by([j], [j.worker, j.state])
      |> order_by([j], [j.worker, j.state])
      |> select([j], [j.worker, j.state, count(j.id)])
      |> Repo.all()
      |> Enum.map(fn [worker, state, count] -> [short(worker), state, count] end)

    {:ok, %{columns: ["worker", "state", "jobs"], rows: rows}}
  end

  defp jobs(worker, since) do
    worker = full(worker)
    query = since |> recent() |> where([j], j.worker == ^worker)

    rows =
      query
      |> group_by([j], j.state)
      |> order_by([j], j.state)
      |> select([j], [j.state, count(j.id)])
      |> Repo.all()

    {:ok, %{columns: ["state", "jobs"], rows: rows, note: newest_error(query)}}
  end

  defp recent(since),
    do: where(Oban.Job, [j], j.inserted_at >= ^since or j.attempted_at >= ^since)

  defp newest_error(query) do
    errors =
      query
      |> where([j], j.state in ["retryable", "discarded"])
      |> order_by([j], desc: j.attempted_at)
      |> limit(1)
      |> select([j], j.errors)
      |> Repo.one()

    case errors && List.last(errors) do
      %{"error" => error} ->
        "Newest error: " <> (error |> String.split("\n") |> hd() |> String.slice(0, 200))

      _ ->
        nil
    end
  end

  defp full("App.Worker." <> _ = worker), do: worker
  defp full(worker), do: "App.Worker." <> String.replace_suffix(worker, "Worker", "") <> "Worker"

  defp short(worker), do: String.replace_prefix(worker, "App.Worker.", "")
end
