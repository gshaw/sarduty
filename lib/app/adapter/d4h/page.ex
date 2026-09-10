defmodule App.Adapter.D4H.Page do
  # One page of a D4H list endpoint:
  # {"results": [...], "page": 0, "pageSize": 1000, "totalSize": 2500}
  defstruct results: [], total_size: 0

  def build(%{"results" => results, "totalSize" => total_size})
      when is_list(results) and is_integer(total_size) do
    {:ok, %__MODULE__{results: results, total_size: total_size}}
  end

  def build(_body), do: :error

  @doc """
  What to do after a page, given how many rows have been fetched so far: `:done` once
  they cover D4H's total, `:next` for another page, or `:short` when D4H ran out of
  rows before its own total.
  """
  def next(%__MODULE__{} = page, fetched_count) do
    cond do
      fetched_count >= page.total_size -> :done
      page.results == [] -> :short
      true -> :next
    end
  end
end
