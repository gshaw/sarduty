defmodule Web.LinkWhitespaceTest do
  use ExUnit.Case, async: true

  # A space or line break before </.a> renders inside the link, so it is underlined and
  # pushes whatever follows away: a badge, a full stop, the next link. The formatter keeps
  # a link written as <.a …>text</.a> on one line (inline_matcher in .formatter.exs).
  test "no link ends with a space" do
    hits =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          Regex.match?(~r/(^|\s)<\/\.a>/, line),
          do: "#{path}:#{number}: #{String.trim(line)}"

    assert hits == [],
           "Put the text against the closing tag, as in <.a …>text</.a>:\n" <>
             Enum.join(hits, "\n")
  end
end
