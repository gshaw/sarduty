defmodule App.ViewModel.MemberDetailsViewModel do
  use App, :view_model

  alias App.Adapter.D4H.MemberDetails
  alias App.Field
  alias App.Validate

  # A member's own address and emergency contacts (#156). Lengths are D4H's.
  @primary_key false
  embedded_schema do
    field :address, Field.TrimmedString
    field :contact1_name, Field.TrimmedString
    field :contact1_relation, Field.TrimmedString
    field :contact1_primary_phone, Field.TrimmedString
    field :contact1_secondary_phone, Field.TrimmedString
    field :contact2_name, Field.TrimmedString
    field :contact2_relation, Field.TrimmedString
    field :contact2_primary_phone, Field.TrimmedString
    field :contact2_secondary_phone, Field.TrimmedString
  end

  @fields [
    :address,
    :contact1_name,
    :contact1_relation,
    :contact1_primary_phone,
    :contact1_secondary_phone,
    :contact2_name,
    :contact2_relation,
    :contact2_primary_phone,
    :contact2_secondary_phone
  ]

  @doc "The form for what D4H holds now."
  def from_details(%MemberDetails{} = details) do
    struct(
      __MODULE__,
      [address: details.address] ++
        contact(:contact1, details.primary_emergency_contact) ++
        contact(:contact2, details.secondary_emergency_contact)
    )
  end

  defp contact(prefix, contact) do
    for {key, value} <- contact || MemberDetails.empty_contact(),
        do: {String.to_existing_atom("#{prefix}_#{key}"), value}
  end

  @doc "The form's values in a change set row's shape: \"address\" and the two contacts."
  def to_values(%__MODULE__{} = form) do
    %{
      "address" => form.address,
      "primary_emergency_contact" => values(form, :contact1),
      "secondary_emergency_contact" => values(form, :contact2)
    }
  end

  defp values(form, prefix) do
    Map.new(MemberDetails.empty_contact(), fn {key, _nil} ->
      {key, Map.fetch!(form, String.to_existing_atom("#{prefix}_#{key}"))}
    end)
  end

  def changeset(%__MODULE__{} = form, params \\ %{}) do
    form
    |> cast(params, @fields)
    |> validate_length(:address, max: 300)
    |> validate_length(:contact1_name, max: 80)
    |> validate_length(:contact1_relation, max: 80)
    |> validate_length(:contact1_primary_phone, max: 100)
    |> validate_length(:contact1_secondary_phone, max: 100)
    |> validate_length(:contact2_name, max: 80)
    |> validate_length(:contact2_relation, max: 80)
    |> validate_length(:contact2_primary_phone, max: 100)
    |> validate_length(:contact2_secondary_phone, max: 100)
    |> Validate.in_field_order(@fields)
  end

  # :insert, not :validate, so a failed save shows the error summary.
  def validate(form, params), do: form |> changeset(params) |> apply_action(:insert)
end
