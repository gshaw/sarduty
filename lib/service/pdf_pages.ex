defmodule Service.PDFPages do
  @moduledoc """
  How many pages a PDF has (#950): a form prints every page of its own page PDF, and
  Typst can draw a PDF's page but can't count them.

  It reads the page tree's root, the `/Pages` dictionary with no `/Parent`, and its
  `/Count`, in the file and in its compressed object streams. An update appended to a
  PDF writes its pages again after the old, so the last root wins, as a reader takes
  it. Not a general PDF parser: a PDF it can't read is `:error`, never a guess.
  """

  # cspell:ignore ObjStm FlateDecode -- PDF syntax names

  @doc "`{:ok, pages}`, or `:error` when it finds no page tree."
  def count(pdf) when is_binary(pdf) do
    roots = pdf |> sources() |> Enum.flat_map(&roots/1)
    if roots == [], do: :error, else: {:ok, List.last(roots)}
  end

  # The file, then each object stream's objects, in the order they're written.
  defp sources(pdf) do
    streams =
      ~r{/Type\s*/ObjStm\b}
      |> Regex.scan(pdf, return: :index)
      |> Enum.flat_map(fn [{at, _length}] -> object_stream(pdf, at) end)

    [pdf | streams]
  end

  # The data of the stream whose dictionary holds `at`, inflated.
  defp object_stream(pdf, at) do
    rest = binary_part(pdf, at, byte_size(pdf) - at)

    with [_dict, data] <- Regex.run(~r/\A(?:(?!stream\b).)*?stream\r?\n(.*?)endstream/s, rest),
         {:ok, inflated} <- inflate(data) do
      [inflated]
    else
      _other -> []
    end
  end

  defp inflate(data) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z)
      {:ok, z |> :zlib.inflate(data) |> IO.iodata_to_binary()}
    rescue
      ErlangError -> :error
    after
      :zlib.close(z)
    end
  end

  # Each `/Pages` dictionary with no `/Parent`: its `/Count`.
  defp roots(text) do
    ~r{/Type\s*/Pages(?![A-Za-z])}
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [{at, _length}] ->
      keys = text |> dictionary(at) |> top_level()

      with false <- Regex.match?(~r{/Parent\b}, keys),
           [_all, count] <- Regex.run(~r{/Count\s+(\d+)}, keys) do
        [String.to_integer(count)]
      else
        _other -> []
      end
    end)
  end

  # The dictionary around `at`: back to its `<<`, then on to its `>>`.
  defp dictionary(text, at) do
    start = open_at(text, at - 1, 0)
    finish = close_at(text, at, 0)
    binary_part(text, start, finish - start)
  end

  defp open_at(_text, i, _depth) when i < 1, do: 0

  defp open_at(text, i, depth) do
    case binary_part(text, i - 1, 2) do
      "<<" when depth == 0 -> i - 1
      "<<" -> open_at(text, i - 2, depth - 1)
      ">>" -> open_at(text, i - 2, depth + 1)
      _other -> open_at(text, i - 1, depth)
    end
  end

  defp close_at(text, i, _depth) when i >= byte_size(text) - 1, do: byte_size(text)

  defp close_at(text, i, depth) do
    case binary_part(text, i, 2) do
      ">>" when depth == 0 -> i + 2
      ">>" -> close_at(text, i + 2, depth - 1)
      "<<" -> close_at(text, i + 2, depth + 1)
      _other -> close_at(text, i + 1, depth)
    end
  end

  # The dictionary's own keys and values, with what's nested in it taken out.
  defp top_level(<<"<<", inner::binary>>) do
    inner |> binary_part(0, max(byte_size(inner) - 2, 0)) |> strip_nested()
  end

  defp top_level(text), do: text

  defp strip_nested(text) do
    stripped = Regex.replace(~r/<<(?:(?!<<|>>).)*>>/s, text, "")
    if stripped == text, do: text, else: strip_nested(stripped)
  end
end
