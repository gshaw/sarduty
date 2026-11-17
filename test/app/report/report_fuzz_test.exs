defmodule App.Report.ReportFuzzTest do
  # Runs each input as a report, and as its page, on Coast Range SAR (App.SampleRepo).
  # `mix test` replays the seeds and saved failures. To fuzz: mise run fuzz
  use ExUnit.Case, async: true
  use ExFuzz

  import ExUnit.CaptureLog

  alias App.Report
  alias App.Report.BuiltIn
  alias App.Report.Context
  alias App.Report.Error

  # Runner's message for SQL that SQLite refused: the compiler wrote it wrong.
  @bad_sql "This report could not run. Try again, or change its query."

  # A fixed date, so a saved failure that depends on THIS_MONTH or LAST_N_DAYS replays.
  @now ~U[2026-11-17 00:00:00Z]

  @tag timeout: 5_000
  fuzz "any text runs or gives a report error",
       data <- binary(),
       seeds: Enum.map(BuiltIn.all(), & &1.query) do
    {run, log} = with_log(fn -> Report.run_sample(data, %{}, @now) end)
    check!(run, log)

    context = Context.new(App.SampleRepo.team(), @now, repo: App.SampleRepo)
    {page, log} = with_log(fn -> Report.page_in(context, data) end)
    check!(page, log)
  end

  defp check!({:ok, _result}, _log), do: :ok

  defp check!({:error, %Error{message: @bad_sql}}, log),
    do: flunk("The compiler wrote SQL that SQLite refused:\n#{log}")

  defp check!({:error, %Error{}}, _log), do: :ok
end
