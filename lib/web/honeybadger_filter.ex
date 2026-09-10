defmodule Web.HoneybadgerFilter do
  @moduledoc """
  Honeybadger's default filter drops `filter_keys` from the top level of the params
  only, so `user[password]` would reach Honeybadger. This filters every level.
  """

  use Honeybadger.Filter.Mixin

  @impl Honeybadger.Filter
  def filter_params(params), do: Honeybadger.Utils.sanitize(params)
end
