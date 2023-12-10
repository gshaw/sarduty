defmodule App.ViewModel.ChangeD4HAccessKeyViewModel do
  use App, :view_model

  alias App.Field.TrimmedString
  alias App.Validate

  embedded_schema do
    field :access_key, TrimmedString
    field :api_host, TrimmedString
  end

  def validate(params) do
    params
    |> build_new_changeset()
    |> Ecto.Changeset.apply_action(:replace)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%__MODULE__{}, params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:access_key, :api_host])
    |> validate_required([:access_key, :api_host])
    |> Validate.d4h_access_key(:access_key, :api_host)

    # |> Validate.d4h_api_host(:api_host)
  end
end
