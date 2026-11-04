defmodule App.ViewModel.DemoStartViewModel do
  use App, :view_model

  alias App.Field

  # Try a demo's one optional field (#857): the visitor's name, for their member on the
  # demo team. Left blank, the member gets a made-up one.
  @primary_key false
  embedded_schema do
    field :name, Field.TrimmedString
  end

  def build_new_changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:name])
    |> validate_length(:name, max: 50, message: "Enter a name of 50 characters or fewer.")
  end

  def validate(params), do: params |> build_new_changeset() |> apply_action(:insert)
end
