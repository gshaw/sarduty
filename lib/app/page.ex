defmodule App.Page do
  @moduledoc """
  One page of a query's results, from `App.Repo.paginate/2`.
  """

  defstruct entries: [], page_number: 1, page_size: 50, total_entries: 0, total_pages: 1

  @type t :: %__MODULE__{
          entries: [any()],
          page_number: pos_integer(),
          page_size: pos_integer(),
          total_entries: non_neg_integer(),
          total_pages: pos_integer()
        }
end
