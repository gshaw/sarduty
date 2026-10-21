defmodule Service.FormatUsageTest do
  use ExUnit.Case, async: true

  # Every value people read goes through a Service.Format function, so it reads the same
  # everywhere and changes in one place (docs/writing.md, rule 10). A number written into
  # text with its unit by hand, such as "{days} days" or "#{km} km", fails here. A HEEx
  # attribute named like a unit (`lines={@lines} km />`) is not text.
  @unit ~r/(#\{[^}]*\}|\{[^}]*\})\s*(days?|weeks?|months?|years?|hours?|minutes?|min|km)\b(?!\s*(=|\/?>))/

  # Lines where the word after a value is not its unit, and why.
  @names %{
    ~s(do: {kind, "Use a different tag from \#{earlier} hours."}) =>
      "primary hours is the name of a kind of hours, not a count"
  }

  test "units come from Service.Format, not written beside a number" do
    hits =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          path != "lib/service/format.ex",
          {line, number} <- text_lines(File.read!(path)),
          Regex.match?(@unit, line),
          not Map.has_key?(@names, String.trim(line)),
          do: "#{path}:#{number}: #{String.trim(line)}"

    assert hits == [],
           "Use a Service.Format function for these values:\n" <> Enum.join(hits, "\n")
  end

  # Numbered lines people read: not comments, docs (heredocs included), or log calls.
  defp text_lines(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_reduce(false, fn {line, number}, in_doc? ->
      trimmed = String.trim(line)
      opens_doc? = Regex.match?(~r/^@(module)?doc\s+(~[sS])?"""/, trimmed)

      cond do
        in_doc? -> {nil, trimmed != ~s(""")}
        opens_doc? -> {nil, true}
        String.starts_with?(trimmed, ["#", "@doc", "@moduledoc"]) -> {nil, false}
        String.contains?(line, "Logger.") -> {nil, false}
        true -> {{line, number}, false}
      end
    end)
    |> elem(0)
    |> Enum.reject(&is_nil/1)
  end
end
