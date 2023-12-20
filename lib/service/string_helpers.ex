defmodule Service.StringHelpers do
  @moduledoc """
    Useful functions for working with strings.
  """

  @doc """
  Truncate the string to a given length.
  """
  def truncate(text, opts \\ []) do
    max_length = opts[:max_length] || 50
    omission = opts[:omission] || "…"

    cond do
      is_nil(text) ->
        nil

      not String.valid?(text) ->
        text

      String.length(text) < max_length ->
        text

      true ->
        length_with_omission = max_length - String.length(omission)

        "#{String.slice(text, 0, length_with_omission)}#{omission}"
    end
  end
end
