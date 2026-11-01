defmodule App.Report.Source do
  @moduledoc """
  A subject's rows when some columns need a join of their own (#784): `query`, scoped to
  the team; `fields`, each column's dynamic; `joins`, each a function that adds a named
  join; and `needs`, the joins each column reads. A report selects only the columns it
  reads, with only their joins, so a page that never shows attendance never adds it up.
  Every join is a left join of at most one row per row, so leaving one out never changes
  which rows there are: a count reads only the columns its where does.
  """

  import Ecto.Query, only: [select: 2]

  @enforce_keys [:query, :fields]
  defstruct [:query, :fields, joins: %{}, needs: %{}]

  @doc """
  The Ecto query for `columns`, always with `id`. A plain query, the shape of a source with
  no joins of its own to leave out, comes back as it is.
  """
  def query(%__MODULE__{} = source, columns) do
    columns = Enum.uniq([:id | columns])
    joins = columns |> Enum.flat_map(&Map.get(source.needs, &1, [])) |> Enum.uniq()
    query = Enum.reduce(joins, source.query, fn name, q -> Map.fetch!(source.joins, name).(q) end)
    select(query, ^Map.new(columns, &{&1, Map.fetch!(source.fields, &1)}))
  end

  def query(%Ecto.Query{} = query, _columns), do: query
end
