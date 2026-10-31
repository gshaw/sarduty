defmodule Check do
  @moduledoc "Compares a list page's own code with the list spec, case by case."

  def start(name), do: Process.put(:results, Map.put(Process.get(:results, %{}), name, []))

  def same(list, label, ours, theirs) do
    ok = ours == theirs
    detail = if ok, do: "", else: diff(ours, theirs)
    record(list, {label, ok, detail})
    IO.puts("#{if ok, do: "  ok  ", else: "  DIFF"} #{list} | #{label}#{detail}")
    ok
  end

  def same_set(list, label, ours, theirs),
    do: same(list, label <> " (as a set)", Enum.sort(ours), Enum.sort(theirs))

  defp diff(ours, theirs) when is_list(ours) and is_list(theirs) do
    extra = ours -- theirs
    missing = theirs -- ours

    " -- spec #{length(ours)}, page #{length(theirs)}" <>
      if(extra == [] and missing == [],
        do: ", same rows in another order",
        else: ", spec only #{inspect(Enum.take(extra, 5))}, page only #{inspect(Enum.take(missing, 5))}"
      )
  end

  defp diff(ours, theirs), do: " -- spec #{inspect(ours)}, page #{inspect(theirs)}"

  defp record(list, result) do
    results = Process.get(:results, %{})
    Process.put(:results, Map.update(results, list, [result], &[result | &1]))
  end

  def summary do
    IO.puts("\n== Summary")

    for {list, results} <- Process.get(:results, %{}) |> Enum.sort() do
      bad = Enum.reject(results, &elem(&1, 1))
      IO.puts("#{list}: #{length(results) - length(bad)}/#{length(results)} match")
    end
  end
end
