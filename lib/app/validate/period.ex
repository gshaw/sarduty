defmodule App.Validate.Period do
  import Ecto.Changeset

  # A filter's period: all, a year, or a rolling period (Service.Period.valid?/1).
  def call(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if Service.Period.valid?(value), do: [], else: [{field, "is invalid"}]
    end)
  end
end
