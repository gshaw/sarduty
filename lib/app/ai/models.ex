defmodule App.AI.Models do
  @moduledoc """
  The Claude models a SAR Duty admin can pick for AI writing, with Anthropic's list prices
  in US dollars per million tokens, as of 2026-11-15. A cache write is the 5-minute
  cache's, 1.25 times the input price. The cost of an ask comes from these, so change a
  price here when Anthropic does.
  """

  @models [
    %{
      id: "claude-sonnet-5-5",
      name: "Claude Sonnet 5.5",
      input: 2.0,
      output: 10.0,
      cache_read: 0.10
    },
    %{
      id: "claude-opus-5-5",
      name: "Claude Opus 5.5",
      input: 4.0,
      output: 20.0,
      cache_read: 0.20
    },
    %{
      id: "claude-haiku-5-5",
      name: "Claude Haiku 5.5",
      input: 0.10,
      output: 0.50,
      cache_read: 0.01
    }
  ]

  @default "claude-sonnet-5-5"

  def all, do: @models
  def ids, do: Enum.map(@models, & &1.id)
  def default, do: @default

  @doc "The model with `id`, or nil."
  def get(id), do: Enum.find(@models, &(&1.id == id))

  @doc "Its name, or the id for a model no longer listed."
  def name(id), do: (get(id) || %{name: id}).name

  @doc """
  What `usage` cost on `id`, in millionths of a dollar. `usage` holds `input`,
  `cache_write`, `cache_read`, and `output` token counts. A model no longer listed
  costs as the default does, so a cost is never left out.
  """
  def cost_microdollars(id, usage) do
    price = get(id) || get(@default)

    round(
      usage.input * price.input + usage.cache_write * price.input * 1.25 +
        usage.cache_read * price.cache_read + usage.output * price.output
    )
  end
end
