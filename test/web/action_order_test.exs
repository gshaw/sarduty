defmodule Web.ActionOrderTest do
  use ExUnit.Case, async: true

  # Every record's Actions run in one order, so a link is where it was on the last record:
  # change the record, send, reports, Open in D4H, Delete. The Detail list page in the
  # style guide says why. Each link ranks by its words; an unknown one counts as a report.
  @ranks [
    {~r/^Change fields/, 2},
    {~r/^Change tags/, 3},
    {~r/^Apply /, 4},
    {~r/^(Change |Rename)/, 1},
    {~r/^Send /, 5},
    {~r/^Open in /, 7},
    {~r/^Delete/, 8}
  ]

  test "every Actions list runs in the style guide's order" do
    lists =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          [list] <- Regex.scan(~r/>Actions<\/dt>.*?<\/ul>/s, File.read!(path)),
          do: {path, Regex.scan(~r/>([^<>]+)<\/\.a>/, list, capture: :all_but_first)}

    assert length(lists) >= 8

    out_of_order =
      for {path, links} <- lists,
          texts = List.flatten(links),
          ranks = Enum.map(texts, &rank/1),
          ranks != Enum.sort(ranks),
          do: "#{path}: #{Enum.join(texts, ", ")}"

    assert out_of_order == [],
           "Order Actions as the style guide's Detail list page says:\n" <>
             Enum.join(out_of_order, "\n")
  end

  defp rank(text) do
    Enum.find_value(@ranks, 6, fn {pattern, rank} -> Regex.match?(pattern, text) && rank end)
  end
end
