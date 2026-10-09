defmodule App.Validate.FieldOrder do
  # Ecto puts each validation's errors first, so a form's error summary would list the
  # last field's problem first. This sorts them into the form's own order.
  def call(%Ecto.Changeset{errors: errors} = changeset, fields) do
    position = fields |> Enum.with_index() |> Map.new()

    %{
      changeset
      | errors:
          Enum.sort_by(errors, fn {field, _error} -> Map.get(position, field, length(fields)) end)
    }
  end
end
