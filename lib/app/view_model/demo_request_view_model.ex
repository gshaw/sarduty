defmodule App.ViewModel.DemoRequestViewModel do
  use App, :view_model

  alias App.Field
  alias App.Validate.Email

  # Try a demo's form (#857): the name joins Coast Range SAR as a team admin, and the
  # email is how they log in.
  @primary_key false
  embedded_schema do
    field :name, Field.TrimmedString
    field :email, Field.TrimmedString
  end

  def build_new_changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:name, :email])
    |> validate_required([:name], message: "Enter your name.")
    |> validate_required([:email], message: "Enter your email.")
    |> validate_length(:name, max: 50, message: "Enter a name of 50 characters or fewer.")
    |> Email.call(:email)
    |> update_change(:email, &String.downcase/1)
  end

  def validate(params), do: params |> build_new_changeset() |> apply_action(:insert)
end
