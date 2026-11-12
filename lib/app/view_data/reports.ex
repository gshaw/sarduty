defmodule App.ViewData.Reports do
  @moduledoc """
  The reports a team admin can run (#768): the team's own, then the built-in ones. Each
  is a map, so a page treats both the same: `id`, `name`, `about`, `query`, `values`,
  `shows` (the subject's label), and for the team's own, `saved`, `made_by`, and
  `made_on`. Deleted reports are apart, under Recently deleted (#834). A team's own report's `id` is its row's, a number; a built-in one's is its
  slug, so the two never meet in a URL.
  """

  alias App.Model.Member
  alias App.Model.ReportVersion
  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Report.BuiltIn
  alias App.Report.Catalog
  alias App.Report.Parser

  @doc "`%{saved: reports, built_in: reports, deleted: reports}`."
  def list(%Team{} = team, now) do
    %{
      saved: team |> SavedReport.get_all() |> Enum.map(&from_saved(&1, team, now)),
      built_in: team |> BuiltIn.for_team() |> Enum.map(&from_built_in/1),
      deleted: team |> SavedReport.get_deleted() |> Enum.map(&from_saved(&1, team, now))
    }
  end

  @doc """
  Who saved the report last and when, and the agent whose draft it came from:
  `%{by: name, on: datetime, agent: name or nil}`, from its latest version.
  """
  def last_saved(%Team{} = team, %SavedReport{} = report, now) do
    version = ReportVersion.latest(report)

    %{
      by: Member.name_for_user(team, version.user, now),
      on: version.inserted_at,
      agent: version.agent
    }
  end

  @doc "The report whose `id` is in the URL, the team's own or built in, or nil."
  def find(%Team{} = team, id, now) do
    case Integer.parse(id) do
      {n, ""} -> team |> SavedReport.get(n) |> then(&(&1 && from_saved(&1, team, now)))
      _slug -> id |> BuiltIn.get() |> built_in_for(team)
    end
  end

  @doc """
  An agent's name to own something: "Claude's", or "an AI agent's" for one that gave no
  name, as AgentClient.display_name/2 calls it.
  """
  def possessive("An AI agent"), do: "an AI agent's"
  def possessive(name), do: "#{name}'s"

  defp built_in_for(nil, _team), do: nil

  defp built_in_for(report, team),
    do: if(BuiltIn.runs?(report, team), do: from_built_in(report))

  defp from_saved(report, team, now) do
    %{
      id: report.id,
      name: report.name,
      about: report.about,
      query: report.query,
      values: report.values || %{},
      shows: shows(report.query),
      saved: report,
      made_by: Member.name_for_user(team, report.created_by_user, now),
      made_on: report.inserted_at
    }
  end

  defp from_built_in(%{slug: slug} = report) do
    report
    |> Map.drop([:slug, :teams])
    |> Map.merge(%{id: slug, values: %{}, shows: shows(report.query)})
    |> Map.merge(%{saved: nil, made_by: nil, made_on: nil})
  end

  # What a report lists, from the subject after its `from`; nil when the query no longer
  # reads.
  defp shows(query) do
    with {:ok, %{from: from}} <- Parser.parse(query),
         %{label: label} <- Catalog.subject(from) do
      label
    else
      _other -> nil
    end
  end
end
