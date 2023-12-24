defmodule Service.PathHelpers do
  @moduledoc """
    Useful functions for working with paths and URIs.
  """

  @doc """
  Build query params for paginated filter results.
  """
  def build_filter_query_params(filter_options) do
    filter_options
    |> Map.from_struct()
    |> Map.reject(fn {k, v} -> k == :page && v <= 1 end)
    |> Map.reject(fn {_, v} -> v == nil end)
  end
end
