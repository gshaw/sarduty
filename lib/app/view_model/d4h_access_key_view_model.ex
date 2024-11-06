defmodule App.ViewModel.D4HAccessKeyViewModel do
  use App, :view_model

  alias App.Field.TrimmedString
  alias App.Validate
  alias App.ViewModel.D4HAccessKeyViewModel

  embedded_schema do
    field :access_key, TrimmedString
    field :api_host, TrimmedString
    # populated by Validate.d4h_access_key
    field :d4h_team_id, :integer, virtual: true
  end

  def validate(params) do
    params
    |> build_new_changeset()
    |> apply_action(:replace)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%D4HAccessKeyViewModel{}, params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:access_key, :api_host])
    |> validate_required([:access_key, :api_host])
    |> Validate.d4h_access_key(:access_key, :api_host, :d4h_team_id)
  end
end
