defmodule App.Report.Lexer do
  @moduledoc """
  Splits a report query into tokens, each with its line. Pure.

  Tokens are `{:word, text, line}` for names and keywords, `{:string, text, line}` for a
  quoted value, `{:number, n, line}`, `{:value, name, line}` for `:name`, and
  `{:symbol, text, line}` for punctuation and operators. `--` starts a comment to the end
  of the line.
  """

  alias App.Report.Error

  @symbols ["<=", ">=", "!=", "<>", "=", "<", ">", "(", ")", ",", ".", ":", "*"]

  @doc "The tokens, or `{:error, %Error{}}` at the first character it cannot read."
  def tokens(text) when is_binary(text), do: scan(text, 1, [])

  defp scan("", _line, acc), do: {:ok, Enum.reverse(acc)}
  defp scan("\r\n" <> rest, line, acc), do: scan(rest, line + 1, acc)
  defp scan("\n" <> rest, line, acc), do: scan(rest, line + 1, acc)
  defp scan(<<c, rest::binary>>, line, acc) when c in [?\s, ?\t, ?\r], do: scan(rest, line, acc)

  defp scan("--" <> rest, line, acc) do
    case String.split(rest, "\n", parts: 2) do
      [_comment, rest] -> scan(rest, line + 1, acc)
      [_comment] -> scan("", line, acc)
    end
  end

  defp scan(<<quote, rest::binary>>, line, acc) when quote in [?', ?"] do
    case string(rest, quote, []) do
      {:ok, text, rest} ->
        scan(rest, line, [{:string, text, line} | acc])

      :error ->
        {:error,
         Error.new(line, "Close the quote: a value starts with #{<<quote>>} and has no end.")}
    end
  end

  defp scan(<<?:, c, _::binary>> = text, line, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    [name | _] = Regex.run(~r/^:([A-Za-z_][A-Za-z0-9_]*)/, text, capture: :all_but_first)
    rest = binary_part(text, byte_size(name) + 1, byte_size(text) - byte_size(name) - 1)
    scan(rest, line, [{:value, name, line} | acc])
  end

  defp scan(<<c, _::binary>> = text, line, acc) when c in ?0..?9 do
    [digits] = Regex.run(~r/^\d+(\.\d+)?/, text)
    rest = binary_part(text, byte_size(digits), byte_size(text) - byte_size(digits))

    number =
      if String.contains?(digits, "."),
        do: String.to_float(digits),
        else: String.to_integer(digits)

    scan(rest, line, [{:number, number, line} | acc])
  end

  defp scan(<<c, _::binary>> = text, line, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    [word] = Regex.run(~r/^[A-Za-z_][A-Za-z0-9_]*/, text)
    rest = binary_part(text, byte_size(word), byte_size(text) - byte_size(word))
    scan(rest, line, [{:word, word, line} | acc])
  end

  defp scan(text, line, acc) do
    case Enum.find(@symbols, &String.starts_with?(text, &1)) do
      nil ->
        <<c::utf8, _::binary>> = text
        {:error, Error.new(line, "Remove #{<<c::utf8>>}: a query cannot use it.")}

      symbol ->
        rest = binary_part(text, byte_size(symbol), byte_size(text) - byte_size(symbol))
        scan(rest, line, [{:symbol, symbol, line} | acc])
    end
  end

  # A quote written twice is one quote inside the value: 'Can''t make it'.
  defp string(<<q, q, rest::binary>>, q, acc), do: string(rest, q, [<<q>> | acc])

  defp string(<<q, rest::binary>>, q, acc),
    do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp string(<<?\n, _::binary>>, _q, _acc), do: :error
  defp string(<<c::utf8, rest::binary>>, q, acc), do: string(rest, q, [<<c::utf8>> | acc])
  defp string("", _q, _acc), do: :error
end
