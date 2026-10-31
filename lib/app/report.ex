defmodule App.Report do
  # cspell:ignore SOQL
  @moduledoc """
  Reports (#768): saved queries in a small language, run on one team's records.

  The language is Google Sheets' QUERY language plus four pieces of Salesforce's SOQL:
  `from`, dotted fields to a parent, date ranges, and `:name` values. A query reads one
  team's fields from App.Report.Catalog and nothing else. See docs/reports.md.
  """

  alias App.Model.Team
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Parser
  alias App.Report.Runner

  @doc """
  Runs `text` on `team`'s records: `{:ok, %App.Report.Result{}}`, or
  `{:error, %App.Report.Error{}}` for a mistake, checked before anything runs. `given`
  holds picked values by name.
  """
  def run(text, %Team{} = team, given \\ %{}, now \\ DateTime.utc_now()) do
    context = Context.new(team, now)

    with {:ok, plan} <- plan(text, context, given) do
      Runner.run(plan, team.timezone)
    end
  end

  @doc "Checks `text` against `team`'s fields without running it: `{:ok, plan}` or `{:error, error}`."
  def check(text, %Team{} = team, given \\ %{}, now \\ DateTime.utc_now()),
    do: plan(text, Context.new(team, now), given)

  defp plan(text, context, given) do
    with {:ok, query} <- Parser.parse(text) do
      Compiler.compile(query, context, given)
    end
  end
end
