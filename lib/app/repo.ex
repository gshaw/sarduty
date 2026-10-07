defmodule App.Repo do
  use Ecto.Repo,
    otp_app: :sarduty,
    adapter: Ecto.Adapters.SQLite3

  import Ecto.Query

  @default_page_size 50
  @max_page_size 1000

  @doc """
  Returns one page of `query` as an `App.Page`.

  Options are `page` (default 1) and `page_size` (default #{@default_page_size}). A page below
  1 is page 1, the page size is capped at #{@max_page_size}, and a page past the end has no
  entries.
  """
  def paginate(query, opts \\ []) do
    page_number = max(opts[:page] || 1, 1)
    page_size = (opts[:page_size] || @default_page_size) |> max(1) |> min(@max_page_size)
    total_entries = count_entries(query)

    entries =
      query
      |> limit(^page_size)
      |> offset(^((page_number - 1) * page_size))
      |> all()

    %App.Page{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: max(ceil(total_entries / page_size), 1)
    }
  end

  # Counts the rows of the query as a subquery. Order and preloads don't change the
  # count, and the select goes because a subquery can't select a whole schema inside a
  # map, which the member list does.
  defp count_entries(query) do
    query
    |> exclude(:preload)
    |> exclude(:order_by)
    |> exclude(:select)
    |> subquery()
    |> select(count())
    |> one()
  end
end
