defmodule App.ViewData.Reports do
  @moduledoc """
  The reports a team admin can run (#768): the team's own, then the built-in ones. Each
  is a map, so a page treats both the same: `id`, `name`, `about`, `query`, `values`,
  `shows` (the subject's label), and for the team's own, `saved`, `made_by`, and
  `made_on`. A team's own report's `id` is its row's, a number; a built-in one's is its
  slug, so the two never meet in a URL.
  """

  alias App.Model.Member
  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Report.BuiltIn
  alias App.Report.Catalog
  alias App.Report.Parser

  @doc "`%{saved: reports, built_in: reports}`."
  def list(%Team{} = team, now) do
    %{
      saved: team |> SavedReport.get_all() |> Enum.map(&from_saved(&1, team, now)),
      built_in: Enum.map(BuiltIn.all(), &from_built_in/1)
    }
  end

  @doc "The report whose `id` is in the URL, the team's own or built in, or nil."
  def find(%Team{} = team, id, now) do
    case Integer.parse(id) do
      {n, ""} -> team |> SavedReport.get(n) |> then(&(&1 && from_saved(&1, team, now)))
      _slug -> id |> BuiltIn.get() |> then(&(&1 && from_built_in(&1)))
    end
  end

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
    |> Map.delete(:slug)
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
