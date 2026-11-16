defmodule App.AI.HistoryLineJob do
  @moduledoc """
  The line in a report's History, written after a save (App.Operation.WriteHistoryLine):
  Claude compares the version before with the one saved and says what changed in one
  line. It gets the two names, descriptions, and queries, nothing else: no tools, no
  rows. A small job, at low effort.
  """

  alias App.AI.Job
  alias App.Model.SavedReport

  @rules """
  You write one line for a report's History in SAR Duty, a web app for search and rescue
  teams. A report is a query in SAR Duty's report language. You get the report as it was
  and as it was just saved. Say what changed for the team admins who read the History.

  - One short sentence in plain words, at most #{SavedReport.max_change()} characters,
    starting with a verb in the past tense: "Added a bar chart of hours."
  - Say what the report now shows or does differently, not how the query is written. No
    field names in backticks, no SQL.
  - When only the name or description changed, say so.
  """

  @schema %{
    "type" => "object",
    "properties" => %{"line" => %{"type" => "string"}},
    "required" => ["line"],
    "additionalProperties" => false
  }

  @doc """
  The job for a save: `before` and `saved` are maps of `name`, `about`, and `query`. Its
  result is `%{line: line}`.
  """
  def build(before, saved) do
    %Job{
      kind: :history_line,
      system: [@rules],
      tools: [],
      prompt: prompt(before, saved),
      schema: @schema,
      finish: &finish/1,
      context: %{},
      ask: saved.name,
      effort: "low"
    }
  end

  defp prompt(before, saved) do
    """
    #{version("Before", before)}

    #{version("Saved", saved)}
    """
  end

  defp version(title, version) do
    """
    #{title}:
    Name: #{version.name}
    Description: #{version.about || "(none)"}
    Query:
    ```
    #{String.trim(version.query || "")}
    ```\
    """
  end

  @doc "The line, cut to What changed's length, or `{:unchanged, \"\"}` for none."
  def finish(output) do
    case String.trim(output["line"] || "") do
      "" -> {:unchanged, ""}
      line -> {:ok, %{line: String.slice(line, 0, SavedReport.max_change())}}
    end
  end
end
