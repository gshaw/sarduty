defmodule App.Report.ReportWordsFuzzTest do
  # The built-in reports with whole words, values, and lines swapped, so nearly every input
  # parses and the fuzzer's coverage lands on the compiler and the SQL. Each runs as a
  # report and as its page on Coast Range SAR (App.SampleRepo).
  # `mix test` replays the seeds and saved failures. To fuzz: mise run fuzz
  use ExUnit.Case, async: true
  use ExFuzz

  import ExUnit.CaptureLog

  alias App.Report
  alias App.Report.BuiltIn
  alias App.Report.Catalog
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Lexer
  alias App.Report.Parser

  # Runner's message for SQL that SQLite refused: the compiler wrote it wrong.
  @bad_sql "This report could not run. Try again, or change its query."

  # The query's date only. The sample data is seeded from today at app start,
  # so a saved failure that depends on THIS_MONTH or LAST_N_DAYS may still not replay.
  @now ~U[2026-11-17 00:00:00Z]

  # A seed per built-in report, unchanged: the first byte picks it.
  @tag timeout: 5_000
  fuzz "built-in reports with words swapped run or give a report error",
       data <- binary(),
       seeds: Enum.map(0..(length(BuiltIn.all()) - 1), &<<&1>>) do
    text = query(data)
    context = Context.new(App.SampleRepo.team(), @now, repo: App.SampleRepo)

    {run, log} = with_log(fn -> Report.run_sample(text, %{}, @now) end)
    check!(run, log, text)

    {page, log} = with_log(fn -> Report.page_in(context, text) end)
    check!(page, log, text)
  end

  defp check!({:ok, _result}, _log, _text), do: :ok

  defp check!({:error, %Error{message: @bad_sql}}, log, text),
    do: flunk("The compiler wrote SQL that SQLite refused.\nquery:\n#{text}\n#{log}")

  defp check!({:error, %Error{}}, _log, _text), do: :ok

  # The first byte picks a built-in report. Each 4 bytes after it are one change: what to
  # do, which line, which token, and which replacement.
  @doc false
  def query(<<>>), do: query(<<0>>)

  def query(<<pick, changes::binary>>) do
    pools = pools()
    lines = Enum.at(pools.reports, rem(pick, length(pools.reports)))
    lines |> change(changes, pools) |> render()
  end

  defp change(lines, <<op, a, b, c, rest::binary>>, pools),
    do: lines |> change(rem(op, 8), a, b, c, pools) |> change(rest, pools)

  defp change(lines, _rest, _pools), do: lines

  # 0: swap a token for a word. 1: swap a symbol. 2: drop a token. 3: put in a word.
  # 4: swap a value. 5: copy a few tokens. 6: put in a line from any report. 7: drop a line.
  defp change([], _op, _a, _b, _c, _pools), do: []

  defp change(lines, 0, a, b, c, pools),
    do: at_token(lines, a, b, &put(&1, &2, pick(pools.words, c)))

  defp change(lines, 1, a, b, c, pools),
    do: at_token(lines, a, b, &put(&1, &2, {:symbol, pick(pools.symbols, c), 1}))

  defp change(lines, 2, a, b, _c, _pools), do: at_token(lines, a, b, &List.delete_at/2)

  defp change(lines, 3, a, b, c, pools),
    do: at_token(lines, a, b, &List.insert_at(&1, &2, pick(pools.words, c)))

  defp change(lines, 4, a, b, c, pools),
    do: at_token(lines, a, b, &put(&1, &2, pick(pools.values, c)))

  defp change(lines, 5, a, b, c, _pools) do
    at_token(lines, a, b, fn tokens, i ->
      tokens |> List.insert_at(i, Enum.slice(tokens, i, rem(c, 6) + 1)) |> List.flatten()
    end)
  end

  defp change(lines, 6, a, _b, c, pools),
    do: List.insert_at(lines, rem(a, length(lines) + 1), pick(pools.lines, c))

  defp change(lines, 7, a, _b, _c, _pools), do: List.delete_at(lines, rem(a, length(lines)))

  defp at_token(lines, a, b, fun) do
    n = rem(a, length(lines))

    List.update_at(lines, n, fn
      [] -> []
      tokens -> fun.(tokens, rem(b, length(tokens)))
    end)
  end

  defp put(tokens, i, token), do: List.replace_at(tokens, i, token)

  defp pick(list, c), do: Enum.at(list, rem(c, length(list)))

  defp render(lines),
    do: Enum.map_join(lines, "\n", fn tokens -> Enum.map_join(tokens, " ", &text/1) end)

  defp text({:word, word, _line}), do: word
  defp text({:symbol, symbol, _line}), do: symbol
  defp text({:value, name, _line}), do: ":" <> name
  defp text({:string, s, _line}), do: "'" <> String.replace(s, "'", "''") <> "'"
  defp text({:date, date, _line}), do: Date.to_iso8601(date)
  defp text({:number, n, _line}) when is_float(n), do: :erlang.float_to_binary(n, [:short])
  defp text({:number, n, _line}), do: Integer.to_string(n)

  # What a change picks from, built once per VM: every built-in report as lines of
  # tokens, and the words, values, and symbols they and Coast Range SAR's catalog use.
  # Sorted, so the same bytes always make the same query.
  defp pools do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        pools = build_pools()
        :persistent_term.put(__MODULE__, pools)
        pools

      pools ->
        pools
    end
  end

  defp build_pools do
    context = Context.new(App.SampleRepo.team(), @now, repo: App.SampleRepo)
    reports = Enum.map(BuiltIn.all(), &lines(&1.query))
    tokens = List.flatten(reports)

    fields = for subject <- Catalog.subjects(), do: Catalog.shown_fields(subject, context)
    fields = List.flatten(fields)

    %{
      reports: reports,
      lines: reports |> Enum.concat() |> Enum.uniq() |> Enum.sort(),
      words: fields |> words(tokens) |> Enum.uniq() |> Enum.sort() |> Enum.map(&{:word, &1, 1}),
      values: fields |> values(tokens, context) |> Enum.uniq() |> Enum.sort(),
      symbols: ~w(<= >= != <> = < > \( \) , . : * + - /)
    }
  end

  defp words(fields, tokens) do
    Enum.map(Catalog.subjects(), & &1.name) ++
      Enum.map(fields, & &1.name) ++
      Parser.functions() ++
      Parser.clauses() ++
      Parser.page_clauses() ++
      Parser.chart_kinds() ++
      ~w(NOW TODAY THIS_MONTH LAST_MONTH THIS_YEAR LAST_YEAR LAST_N_DAYS NEXT_N_DAYS LAST_N_MONTHS) ++
      for({:word, word, _} <- tokens, do: word)
  end

  defp values(fields, tokens, context) do
    literals = for token <- tokens, elem(token, 0) in [:string, :number, :date, :value], do: token

    literals ++
      Enum.map(
        choices(fields, context) ++ ["", "x", "O'Brien", "all", "90d", "2026"],
        &{:string, &1, 1}
      ) ++
      Enum.map([0, 1, 2, 500, 501, 999_999_999_999_999_999, 0.5], &{:number, &1, 1}) ++
      Enum.map([~D[1900-01-01], ~D[2026-02-28], ~D[2100-12-31]], &{:date, &1, 1}) ++
      Enum.map(~w(year when tag items n group), &{:value, &1, 1})
  end

  defp choices(fields, context) do
    for %{choices: choices} <- fields,
        is_function(choices, 1),
        {_label, value} <- choices.(context),
        is_binary(value),
        do: value
  end

  # A query's tokens, a list per line.
  defp lines(text) do
    {:ok, tokens} = Lexer.tokens(text)

    tokens
    |> Enum.chunk_by(&elem(&1, 2))
    |> Enum.map(fn line -> Enum.map(line, &put_elem(&1, 2, 1)) end)
  end
end
