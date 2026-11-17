defmodule App.Report.ParserFuzzTest do
  # `mix test` replays the seeds and saved failures. To fuzz: mix fuzz test/app/report/parser_fuzz_test.exs:12
  use ExUnit.Case, async: true
  use ExFuzz

  alias App.Report.Error
  alias App.Report.Parser
  alias App.Report.Query

  @tag timeout: 200
  fuzz "any text parses or gives a report error",
       data <- binary(),
       seeds: [
         "select title from activities where hours > 0.25",
         "SELECT member, sum(hours)\nfrom attendance\nwhere status = 'Attended' and year(activity.started_at) = :year\ngroup by member\npivot activity.kind\norder by member.name desc\nlimit 10 offset 5\nlabel sum(hours) 'Hours'\ntotals",
         "select count(distinct member) from attendance where status = 'Can''t make it'",
         "select name from members where (a + b) * c / 2 - d > 15% and joined_at > 2026-04-15 and x > -5",
         "select title from activities\nsort id 'ID' ref_id",
         "select month(started_at), count(id) from activities group by month(started_at) pivot kind\npage 50"
       ] do
    case Parser.parse(data) do
      {:ok, %Query{}} -> :ok
      {:error, %Error{}} -> :ok
    end
  end
end
