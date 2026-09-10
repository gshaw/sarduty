defmodule App.Operation.RefreshD4HData.StaleRows do
  import Ecto.Query

  alias App.Repo

  @doc """
  Local ids of the rows in `query` whose D4H id the refresh didn't see. `query` must
  already be scoped to one team. Only call this after a complete fetch; the adapter
  raises on a short one.
  """
  def ids(query, d4h_id_field, synced_d4h_ids) do
    query
    |> select([r], {r.id, field(r, ^d4h_id_field)})
    |> Repo.all()
    |> Enum.reject(fn {_id, d4h_id} -> MapSet.member?(synced_d4h_ids, d4h_id) end)
    |> Enum.map(fn {id, _d4h_id} -> id end)
  end
end
