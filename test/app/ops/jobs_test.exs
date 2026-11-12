defmodule App.Ops.JobsTest do
  use App.DataCase

  alias App.Ops.Jobs

  defp job!(worker, state, minutes_ago, errors \\ []) do
    at = DateTime.add(DateTime.utc_now(), -minutes_ago, :minute)

    Repo.insert!(%Oban.Job{
      worker: worker,
      queue: "default",
      args: %{},
      state: state,
      errors: errors,
      inserted_at: at,
      scheduled_at: at,
      attempted_at: at
    })
  end

  setup do
    job!("App.Worker.SendReminderWorker", "completed", 5)
    job!("App.Worker.SendReminderWorker", "completed", 10)

    job!("App.Worker.SendReminderWorker", "retryable", 20, [
      %{"error" => "boom\nstack", "attempt" => 1}
    ])

    job!("App.Worker.SendReminderWorker", "completed", 120)
    job!("App.Worker.PruneEventsWorker", "completed", 30)
    :ok
  end

  test "counts the last hour's jobs by worker and state" do
    assert {:ok, %{columns: ["worker", "state", "jobs"], rows: rows}} = Jobs.run([])

    assert rows == [
             ["PruneEventsWorker", "completed", 1],
             ["SendReminderWorker", "completed", 2],
             ["SendReminderWorker", "retryable", 1]
           ]
  end

  test "one worker's jobs, with the newest error, however the worker is named" do
    for name <- ["SendReminder", "SendReminderWorker", "App.Worker.SendReminderWorker"] do
      assert {:ok, %{rows: [["completed", 2], ["retryable", 1]], note: "Newest error: boom"}} =
               Jobs.run([name])
    end

    assert {:ok, %{rows: [["completed", 2]], note: nil}} =
             Jobs.run(["SendReminder", "--minutes", "15"])
  end

  test "refuses arguments it doesn't know" do
    for args <- [["a", "b"], ["--minutes", "0"], ["--hours", "1"]] do
      assert {:error, "Usage: jobs [WORKER] [--minutes N]"} = Jobs.run(args)
    end
  end
end
