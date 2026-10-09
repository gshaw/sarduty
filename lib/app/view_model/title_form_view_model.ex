defmodule App.ViewModel.TitleFormViewModel do
  use App, :view_model

  alias App.Field

  # A record that is only a title: a hosted team's qualification or group.
  @primary_key false
  embedded_schema do
    field :title, Field.TrimmedString
  end

  def changeset(%__MODULE__{} = form, params, max_length) do
    form
    |> cast(params, [:title])
    |> validate_required([:title], message: "Enter a title.")
    |> validate_length(:title, max: max_length)
  end

  def validate(form, params, max_length),
    do: form |> changeset(params, max_length) |> apply_action(:insert)
end
