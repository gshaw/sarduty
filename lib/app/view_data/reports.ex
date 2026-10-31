defmodule App.ViewData.Reports do
  @moduledoc """
  The reports a team admin can run (#768): the team's own, then the built-in ones. Each
  is a map, so a page treats both the same: `slug`, `name`, `about`, `query`, `values`,
  `shows` (the subject's label), and for the team's own, `saved`, `made_by`, and
  `made_on`.
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

  @doc "The report with `slug`, the team's own or built in, or nil."
  def find(%Team{} = team, slug, now) do
    case SavedReport.get_by_slug(team, slug) do
      %SavedReport{} = report -> from_saved(report, team, now)
      nil -> slug |> BuiltIn.get() |> then(&(&1 && from_built_in(&1)))
    end
  end

  defp from_saved(report, team, now) do
    %{
      slug: report.slug,
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

  defp from_built_in(report),
    do: Map.merge(report, %{values: %{}, shows: shows(report.query), saved: nil})

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
