defmodule ListSpec do
  @moduledoc """
  Experiment (#768 list views): a prototype of the list clauses a report could add, so a
  report describes its page as well as its rows.

      search title, ref_id
      switch activity 'Kind'
        option incident 'Incidents' where kind = 'incident'
      filter when 'When' [default <value>] [required]
        option past 'Past' where started_at <= NOW
        each year(started_at) where year(started_at) = :when
      sort date 'Date' started_at [desc]
      page 50

  Everything above the first clause is a plain report. A clause turns into plain report
  text: an option's `where` is ANDed in, a search ORs `contains :q` over its fields, a
  switch's counts run once per option with the search left out, a sort is `order by`, and
  a page is `limit` and `offset`. Nothing here runs SQL of its own: every query goes
  through App.Report.run/4, so the catalog checks every name.
  """

  defstruct base: "", search: [], filters: [], sorts: [], page: nil

  @clause ~r/^(search|switch|filter|sort|page)\b/

  def parse(text) do
    lines = String.split(text, "\n")
    {base, clauses} = Enum.split_while(lines, &(not Regex.match?(@clause, &1)))

    clauses
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.reduce(%__MODULE__{base: Enum.join(base, "\n")}, &clause/2)
    |> then(&%{&1 | filters: Enum.reverse(&1.filters), sorts: Enum.reverse(&1.sorts)})
  end

  defp clause("search " <> fields, spec),
    do: %{spec | search: fields |> String.split(",") |> Enum.map(&String.trim/1)}

  defp clause("page " <> n, spec), do: %{spec | page: String.to_integer(String.trim(n))}

  defp clause("sort " <> rest, spec) do
    [_, value, label, expr] = Regex.run(~r/^(\S+) '([^']*)' (.+)$/, String.trim(rest))
    %{spec | sorts: [%{value: value, label: label, expr: expr} | spec.sorts]}
  end

  defp clause("  " <> option, %{filters: [filter | rest]} = spec),
    do: %{spec | filters: [add_option(filter, String.trim(option)) | rest]}

  defp clause(line, spec) do
    [_, kind, name, label, flags] = Regex.run(~r/^(switch|filter) (\S+) '([^']*)'(.*)$/, line)
    default = Regex.run(~r/default (\S+)/, flags, capture: :all_but_first)

    filter = %{
      kind: String.to_atom(kind),
      name: name,
      label: label,
      default: default && hd(default),
      required: flags =~ "required",
      options: [],
      each: nil
    }

    %{spec | filters: [filter | spec.filters]}
  end

  defp add_option(filter, "option " <> rest) do
    [_, value, label, where] = Regex.run(~r/^(\S+) '([^']*)'(?: where (.+))?$/, rest) |> pad4()
    %{filter | options: filter.options ++ [%{value: value, label: label, where: blank(where)}]}
  end

  defp add_option(filter, "each " <> rest) do
    [_, source, where] = Regex.run(~r/^(.+?)(?: where (.+))?$/, rest) |> pad()
    %{filter | each: %{source: source, where: blank(where)}}
  end

  defp pad4([all, value, label]), do: [all, value, label, ""]
  defp pad4(parts), do: parts

  defp pad([all, source]), do: [all, source, ""]
  defp pad(parts), do: parts

  defp blank(""), do: nil
  defp blank(text), do: text

  @doc """
  The plain report text for `picks` (filter name => option value, "all" or missing for
  All), and the values it runs with.
  """
  def desugar(spec, picks, opts \\ []) do
    conditions =
      spec.filters
      |> Enum.reject(&(&1.name in Keyword.get(opts, :skip, [])))
      |> Enum.flat_map(&condition(&1, Map.get(picks, &1.name, &1.default || "all")))

    conditions =
      if Keyword.get(opts, :search, true) and present?(picks["q"]) and spec.search != [],
        do: conditions ++ ["(" <> Enum.map_join(spec.search, " or ", &"#{&1} contains :q") <> ")"],
        else: conditions

    text = add_where(spec.base, conditions ++ Keyword.get(opts, :also, []))
    text = if opts[:select], do: replace_select(text, opts[:select]), else: text

    text =
      case {opts[:count], sort(spec, picks["sort"])} do
        {true, _} -> strip_order(text)
        {_, nil} -> text
        {_, order} -> strip_order(text) <> "\norder by " <> order
      end

    text =
      case {opts[:count], spec.page, picks["page"]} do
        {true, _, _} -> text
        {_, nil, _} -> text
        {_, n, page} -> text <> "\nlimit #{n} offset #{(to_int(page) - 1) * n}"
      end

    defaults = for %{default: d, name: n} when d != nil <- spec.filters, into: %{}, do: {n, d}

    given =
      defaults
      |> Map.merge(Map.drop(picks, ["sort", "page"]))
      |> Map.reject(fn {_k, v} -> v in [nil, ""] end)
    {text, given}
  end

  defp condition(filter, value) do
    case Enum.find(filter.options, &(&1.value == value)) do
      nil when value == "all" -> []
      %{where: nil} -> []
      %{where: where} -> ["(" <> where <> ")"]
      nil when filter.each != nil and filter.each.where == nil -> []
      nil when filter.each != nil -> ["(" <> filter.each.where <> ")"]
      nil -> raise "#{filter.name} has no option #{value}"
    end
  end

  defp sort(_spec, nil), do: nil

  defp sort(spec, value) do
    {key, dir} =
      if String.ends_with?(value, "-"),
        do: {String.trim_trailing(value, "-"), "desc"},
        else: {value, "asc"}

    %{expr: expr} = Enum.find(spec.sorts, &(&1.value == key)) || raise "no sort #{value}"

    # The first key takes the direction; a sort written `expr desc` turns the arrow round,
    # as Duration does today. Keys after a comma break ties, as written.
    [first | ties] = String.split(expr, ", ")

    first =
      case String.split(first, " ") do
        [field, "desc"] -> "#{field} #{if dir == "asc", do: "desc", else: "asc"}"
        [field, "nulls", where] -> "#{field} #{dir} nulls #{where}"
        _ -> "#{first} #{dir}"
      end

    Enum.join([first | ties], ", ")
  end

  defp add_where(text, []), do: text

  defp add_where(text, conditions) do
    joined = Enum.join(conditions, " and ")

    cond do
      text =~ ~r/^where /m ->
        Regex.replace(~r/^where (.+)$/m, text, "where (\\1) and #{joined}", global: false)

      true ->
        Regex.replace(~r/^(from \S+)$/m, text, "\\1\nwhere #{joined}", global: false)
    end
  end

  defp replace_select(text, select), do: Regex.replace(~r/^select .+$/m, text, "select " <> select)
  defp strip_order(text), do: Regex.replace(~r/\norder by .+$/m, text, "")

  defp present?(nil), do: false
  defp present?(text), do: String.trim(text) != ""

  defp to_int(nil), do: 1
  defp to_int(n) when is_integer(n), do: n
  defp to_int(n), do: String.to_integer(n)

  # Running

  @doc "Every row's first column (the id), across pages, for `picks`."
  def ids(spec, team, picks, now) do
    {text, given} = desugar(%{spec | page: nil}, Map.delete(picks, "page"), [])
    run_ids(text, team, given, now)
  end

  @doc "One page's ids and the total, as a list page shows them."
  def page(spec, team, picks, now) do
    {text, given} = desugar(spec, picks)
    {count_text, _} = desugar(spec, picks, count: true, select: "count(id)")
    {run_ids(text, team, given, now), run_one(count_text, team, given, now)}
  end

  @doc "The switch's count for each option: every other filter on, the search off."
  def counts(spec, team, picks, now) do
    switch = Enum.find(spec.filters, &(&1.kind == :switch))

    Map.new(switch.options, fn option ->
      {text, given} =
        desugar(spec, Map.put(picks, switch.name, option.value),
          count: true,
          search: false,
          select: "count(id)"
        )

      {option.value, run_one(text, team, given, now)}
    end)
  end

  def run_ids(text, team, given, now) do
    case App.Report.run(text, team, given, now) do
      {:ok, result} -> Enum.map(result.rows, &hd/1)
      {:error, error} -> raise "report failed: #{App.Report.Error.text(error)}\n#{text}"
    end
  end

  def run_one(text, team, given, now) do
    [[n]] =
      case App.Report.run(text, team, given, now) do
        {:ok, result} -> result.rows
        {:error, error} -> raise "report failed: #{App.Report.Error.text(error)}\n#{text}"
      end

    n
  end
end
