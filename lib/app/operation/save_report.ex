defmodule App.Operation.SaveReport do
  @moduledoc """
  Saves a team admin's report (#768), new or changed. Its query must run on the team's
  fields: a mistake goes on the Query field with its line, as the editor shows it. Every
  save appends a version (#834), with What changed when changing a saved report. Delete
  moves a report to Recently deleted for 30 days, and Restore brings it back.
  """

  alias App.Accounts.User
  alias App.Model.ReportVersion
  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Repo
  alias App.Report
  alias App.Report.Error
  alias Ecto.Changeset

  @doc """
  `{:ok, report}`, or `{:error, changeset}` with what to fix. `agent` names the agent
  whose link the query came from (#816), or nil when a team admin wrote it.
  """
  def call(
        %Team{} = team,
        %User{} = user,
        report,
        params,
        now \\ DateTime.utc_now(),
        agent \\ nil
      ) do
    report = report || %SavedReport{team_id: team.id, created_by_user_id: user.id}

    changeset =
      report
      |> SavedReport.changeset(params)
      |> agent(agent)
      |> check_query(team, now)

    # A new report's description already says what it is.
    change = if report.id, do: Changeset.get_change(changeset, :change)

    Repo.transact(fn ->
      with {:ok, saved} <- Repo.insert_or_update(changeset) do
        saved |> ReportVersion.build(user.id, change, agent) |> Repo.insert!()
        {:ok, saved}
      end
    end)
  end

  @doc "Moves the report to Recently deleted. Its rows were never kept, so nothing else goes."
  def delete(%SavedReport{} = report, now \\ DateTime.utc_now()),
    do: report |> Changeset.change(deleted_at: DateTime.truncate(now, :second)) |> Repo.update!()

  @doc "Brings back the team's deleted report with `id`: `{:ok, report}`, or `:error`."
  def restore(%Team{} = team, id) do
    case SavedReport.get_deleted(team, id) do
      nil -> :error
      report -> {:ok, report |> Changeset.change(deleted_at: nil) |> Repo.update!()}
    end
  end

  defp agent(changeset, nil), do: changeset
  defp agent(changeset, agent), do: Changeset.force_change(changeset, :agent, agent)

  defp check_query(%Changeset{valid?: false} = changeset, _team, _now), do: changeset

  defp check_query(changeset, team, now) do
    query = Changeset.get_field(changeset, :query)
    values = Changeset.get_field(changeset, :values) || %{}

    case Report.check(query, team, values, now) do
      {:ok, _plan} -> changeset
      {:error, error} -> Changeset.add_error(changeset, :query, Error.text(error))
    end
  end
end
