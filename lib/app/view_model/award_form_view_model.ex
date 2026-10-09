defmodule App.ViewModel.AwardFormViewModel do
  use App, :view_model

  # Awarding a qualification to a hosted team's member. Days on the team's clock.
  @primary_key false
  embedded_schema do
    field :qualification_id, :integer
    field :starts_on, :date
    field :ends_on, :date
  end

  def changeset(%__MODULE__{} = form, params \\ %{}) do
    form
    |> cast(params, [:qualification_id, :starts_on, :ends_on])
    |> validate_required([:qualification_id], message: "Select a qualification.")
    |> validate_required([:starts_on], message: "Enter the day it starts.")
    |> validate_ends_after_starts()
    |> App.Validate.in_field_order([:qualification_id, :starts_on, :ends_on])
  end

  defp validate_ends_after_starts(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.compare(ends_on, starts_on) != :gt,
      do: add_error(changeset, :ends_on, "Enter an end after the start."),
      else: changeset
  end

  # :insert, not :validate, so a failed save shows the error summary.
  def validate(form, params), do: form |> changeset(params) |> apply_action(:insert)
end
