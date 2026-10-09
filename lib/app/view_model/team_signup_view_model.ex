defmodule App.ViewModel.TeamSignupViewModel do
  use App, :view_model

  alias App.Adapter.D4H
  alias App.Field

  @primary_key false
  embedded_schema do
    field :email, Field.TrimmedString
    field :api_host, :string
    field :access_key, Field.TrimmedString
  end

  def build_new_changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:email, :api_host, :access_key])
    |> validate_required([:email, :api_host, :access_key])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "Enter an email with an @ sign and no spaces."
    )
    |> validate_length(:email, max: 160)
    |> validate_inclusion(:api_host, D4H.service_hosts(), message: "Select a D4H region.")
    |> validate_length(:access_key, min: 5, max: 2000)
  end

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :insert) do
      {:ok, view_model} -> {:ok, view_model}
      {:error, changeset} -> {:error, changeset}
    end
  end
end
