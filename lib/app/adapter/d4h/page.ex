defmodule App.Adapter.D4H.Page do
  # One page of a D4H list endpoint:
  # {"results": [...], "page": 0, "pageSize": 1000, "totalSize": 2500}
  defstruct results: [], total_size: 0

  def build(%{"results" => results, "totalSize" => total_size})
      when is_list(results) and is_integer(total_size) do
    {:ok, %__MODULE__{results: results, total_size: total_size}}
  end

  def build(_body), do: :error

  @doc "How many pages of `size` rows hold D4H's total. At least one, to learn the total."
  def count(%__MODULE__{total_size: total_size}, size), do: max(1, ceil(total_size / size))

  @doc """
  `:ok` once the fetched rows cover D4H's total, `:short` when D4H ran out of rows first.
  The refresh deletes what D4H didn't return, so a short fetch must never pass.
  """
  def check(%__MODULE__{total_size: total_size}, fetched_count),
    do: if(fetched_count >= total_size, do: :ok, else: :short)
end
