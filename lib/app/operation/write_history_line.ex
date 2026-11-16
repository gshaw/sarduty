defmodule App.Operation.WriteHistoryLine do
  @moduledoc """
  What changed, written by AI a few seconds after a save (docs/ai-writing.md). With AI
  writing open to the team admin who saved, the editor drops What changed, and SaveReport
  queues this. Claude compares the version before with the one saved
  (App.AI.HistoryLineJob), so the line covers every ask, any typing, and any Undo. It
  runs through App.Operation.AskAI, so it has a row and counts toward the monthly budget,
  never the daily limit. With AI writing off or paused by then, the line stays blank.
  """

  alias App.Accounts
  alias App.AI.HistoryLineJob
  alias App.Model.ReportVersion
  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Operation.AskAI
  alias App.Repo

  @doc """
  Whether a save by `user` gets its line from AI: a change to a saved report, with no
  What changed typed, while AI writing is open to them and the budget isn't spent.
  """
  def writes?(%Team{} = team, user, %SavedReport{id: id}, change, now)
      when is_integer(id) and change in [nil, ""],
      do: AskAI.check(team, user, now, :history_line) == :ok

  def writes?(_team, _user, _report, _change, _now), do: false

  @doc """
  Writes the line on the version with `version_id`: `:ok`, or `{:error, reason}` when a
  retry may get it, the API busy or unreachable. Nothing to write is `:ok`.
  """
  def call(version_id, now \\ DateTime.utc_now()) do
    case to_write(version_id) do
      {version, before, report} -> write(version, before, report, now)
      nil -> :ok
    end
  end

  # The version, the one before it, and its report, when there is a line to write.
  defp to_write(version_id) do
    with %ReportVersion{change: nil, user_id: user_id} = version when user_id != nil <-
           Repo.get(ReportVersion, version_id),
         %ReportVersion{} = before <- ReportVersion.previous(version),
         true <- fields(before) != fields(version),
         %SavedReport{} = report <- Repo.get(SavedReport, version.report_id) do
      {version, before, report}
    else
      _nothing_to_write -> nil
    end
  end

  defp write(version, before, report, now) do
    team = Team.get!(report.team_id)
    user = Accounts.get_user!(version.user_id)
    job = before |> fields() |> HistoryLineJob.build(fields(version))

    case AskAI.call(team, user, job, now) do
      {:ok, %{line: line}} ->
        ReportVersion.put_change!(version, line)
        :ok

      {:error, reason} when reason in [:busy, :unreachable] ->
        {:error, reason}

      _no_line ->
        :ok
    end
  end

  defp fields(version), do: Map.take(version, [:name, :about, :query])
end
