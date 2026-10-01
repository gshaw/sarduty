defmodule App.RateLimit do
  @moduledoc """
  Hammer's in-memory counters. Production is one Fly machine, so ETS is enough.
  """

  use Hammer, backend: :ets
end
