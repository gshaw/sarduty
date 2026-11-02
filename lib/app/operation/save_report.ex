defmodule App.Operation.SaveReport do
  @moduledoc """
  Saves a team admin's report (#768), new or changed. Its query must run on the team's
  fields: a mistake goes on the Query field with its line, as the editor shows it.
  """

  alias App.Accounts.User
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

    report
    |> SavedReport.changeset(params)
    |> agent(agent)
    |> check_query(team, now)
    |> Repo.insert_or_update()
  end

  @doc "Deletes the report. Its rows were never kept, so nothing else goes."
  def delete(%SavedReport{} = report), do: Repo.delete!(report)

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
