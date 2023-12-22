defmodule App.Field do
  alias Ecto.Changeset

  def truncate(changeset, field, max_length: max_length) do
    current_value = Changeset.get_field(changeset, field) || ""

    if String.length(current_value) > max_length do
      Changeset.put_change(changeset, field, String.slice(current_value, 0, max_length))
    else
      changeset
    end
  end
end
