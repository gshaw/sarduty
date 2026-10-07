defmodule App.MCP.Tool.HistoryOutput do
  @moduledoc """
  The output of the history tools. Pure. Leaves out who sent a change, an account's
  email, which the page shows and agents don't need.
  """

  alias App.MCP.Output
  alias App.ViewData.ChangeHistory

  def fields, do: ~w(at seen_after by kind change reason source)

  @doc "History entries from App.ViewData.ChangeHistory, as tool output."
  def build(entries, timezone) do
    Enum.map(entries, fn entry ->
      %{
        "at" => Output.datetime(entry.at, timezone),
        "seen_after" => Output.datetime(entry.seen_after, timezone),
        "by" => if(entry.by == :d4h, do: "d4h", else: "sar_duty"),
        "kind" => Atom.to_string(entry.kind),
        "change" => entry.text,
        "reason" => entry[:reason],
        "source" => entry[:source] && ChangeHistory.source_label(entry.source)
      }
    end)
  end
end
