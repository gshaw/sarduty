defmodule App.Field.TrimmedString do
  def type, do: :string
  def cast(data) when is_binary(data), do: {:ok, String.trim(data)}
  def cast(data), do: Ecto.Type.cast(:string, data)
  def load(data), do: Ecto.Type.load(:string, data)
  def dump(data), do: Ecto.Type.dump(:string, data)
  def equal?(a, b), do: a === b
end
