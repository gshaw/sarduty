defmodule App.Validate.Name do
  import Ecto.Changeset

  def max_length, do: 50

  def call(changeset, field) do
    changeset
    |> validate_length(field, max: max_length())
  end
end
