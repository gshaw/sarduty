defmodule App.ViewModel.CustomFieldFormViewModel do
  use App, :view_model

  alias App.Field
  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle

  # Add field and Change field (#1056 step 4): a team's own custom field. The rules are
  # D4H's, and SAR Duty Records keeps the same ones. `target` and `field_type` are set
  # once, when the field is added: D4H's PATCH takes neither.
  @primary_key false
  embedded_schema do
    field :target, :string
    field :title, Field.TrimmedString
    field :field_type, :string
    # Each `%{"id" => d4h_option_id or nil, "label" => …, "archived" => boolean}`, in
    # order. A new one has no id. A choice is archived, never deleted: D4H has no DELETE.
    field :choices, {:array, :map}, default: []
    field :hint, Field.TrimmedString
    field :value_units, Field.TrimmedString
    # A bundle of the team's own for this kind, by its title, or a new name, which adds
    # one. Blank for none.
    field :bundle, Field.TrimmedString
    field :required, :boolean, default: false
    field :restricted, :boolean, default: false
    field :member_privacy, :string, default: "hidden"
  end

  @types ~w(text text_area number date datetime time single_choice multiple_choice)
  @privacies ~w(hidden viewable editable)
  @title_max 150
  @units_max 10
  @bundle_max 80

  @doc "D4H's types, in the order Add field lists them."
  def types, do: @types

  @doc "A new field's form, on `target`: hidden from members, as D4H's default."
  def new(target), do: %__MODULE__{target: target}

  @doc "Change field: the field as the copy has it."
  def from_field(%CustomField{} = field) do
    %__MODULE__{
      target: field.target,
      title: field.title,
      field_type: field.field_type,
      choices:
        for(
          option <- Enum.sort_by(field.options, & &1["ordering"]),
          option["owner_type"] != "Organisation",
          do: Map.take(option, ~w(id label archived))
        ),
      hint: field.hint,
      value_units: field.value_units,
      bundle: field.bundle && field.bundle.title,
      required: field.required,
      restricted: field.restricted,
      member_privacy: field.member_privacy || "hidden"
    }
  end

  @doc """
  Checks a field against D4H's rules. `fields` are the team's fields, its
  organization's too, so a name another live field of the kind has is refused. `field`
  is the one being changed, or nil for Add field.
  """
  def changeset(%__MODULE__{} = form, params, fields, field \\ nil) do
    form
    |> cast(normalize(params), cast_keys(field))
    |> validate_required([:title], message: "Enter a name.")
    |> validate_length(:title,
      max: @title_max,
      message: "Enter a name of #{Service.Format.characters(@title_max)} or fewer."
    )
    |> validate_format(:title, ~r/\A[^|]*\z/, message: "Enter a name without a | in it.")
    |> validate_title_free(fields, field)
    |> validate_inclusion(:target, CustomField.targets(), message: "Select what it is on.")
    |> validate_required([:field_type], message: "Select a type.")
    |> validate_inclusion(:field_type, @types, message: "Select a type.")
    |> validate_choices()
    |> validate_length(:value_units,
      max: @units_max,
      message: "Enter units of #{Service.Format.characters(@units_max)} or fewer."
    )
    |> validate_length(:bundle,
      max: @bundle_max,
      message: "Enter a bundle name of #{Service.Format.characters(@bundle_max)} or fewer."
    )
    |> validate_inclusion(:member_privacy, @privacies, message: "Select what members do.")
  end

  # Kind and type are set once.
  defp cast_keys(nil),
    do: ~w(target title field_type choices hint value_units bundle required restricted
           member_privacy)a

  defp cast_keys(%CustomField{}),
    do: ~w(title choices hint value_units bundle required restricted member_privacy)a

  # Choices come from the form as an indexed map, or from #875's import templates as a
  # list of labels.
  defp normalize(params) do
    case params["choices"] || params[:choices] do
      nil -> params
      choices -> params |> Map.drop([:choices]) |> Map.put("choices", choices(choices))
    end
  end

  defp choices(choices) when is_map(choices),
    do:
      choices
      |> Enum.sort_by(fn {key, _} -> index(key) end)
      |> Enum.map(&elem(&1, 1))
      |> choices()

  defp choices(choices) when is_list(choices) do
    for choice <- choices do
      choice = if is_binary(choice), do: %{"label" => choice}, else: choice

      %{
        "id" => id(choice["id"]),
        "label" => choice["label"] |> to_string() |> String.trim(),
        "archived" => choice["archived"] in [true, "true"]
      }
    end
  end

  defp index(key) do
    case key |> to_string() |> Integer.parse() do
      {n, ""} -> n
      _ -> 0
    end
  end

  # The operation looks each id up among the field's own choices.
  defp id(id) when is_integer(id), do: id

  defp id(id) do
    case id |> to_string() |> Integer.parse() do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp validate_title_free(changeset, fields, field) do
    title = get_field(changeset, :title)
    target = get_field(changeset, :target)

    if title && CustomField.title_taken?(fields, target, title, field),
      do: add_error(changeset, :title, "Enter a name no other field on #{kind(target)} has."),
      else: changeset
  end

  defp kind(target), do: target |> CustomField.target_title() |> String.downcase()

  # A choice field needs one live choice, and every label once.
  defp validate_choices(changeset) do
    with true <- get_field(changeset, :field_type) in ~w(single_choice multiple_choice),
         message when is_binary(message) <- choices_error(get_field(changeset, :choices)) do
      add_error(changeset, :choices, message)
    else
      _ -> changeset
    end
  end

  defp choices_error(choices) do
    labels = Enum.map(choices, &String.downcase(&1["label"]))

    cond do
      "" in labels -> "Enter a name for each choice."
      Enum.all?(choices, & &1["archived"]) -> "Enter at least 1 choice."
      Enum.any?(labels, &(String.length(&1) > @title_max)) -> choices_too_long()
      Enum.uniq(labels) != labels -> "Enter each choice once."
      true -> nil
    end
  end

  defp choices_too_long,
    do: "Enter choices of #{Service.Format.characters(@title_max)} or fewer."

  @doc """
  The field's settings as the adapter takes them, without its choices or bundle. Units
  go only on a number, Needed to publish only on an activity's field, and member
  privacy only on a member's. Restricted is the box on an activity's field, and set for
  the kind on the others, as D4H's default is RESTRICTED (decided 2026-11-13).
  """
  def value(%__MODULE__{} = form) do
    %{
      "title" => form.title,
      "hint" => form.hint,
      "value_units" => if(form.field_type == "number", do: form.value_units),
      "required" => CustomField.activity_target?(form.target) and form.required,
      "restricted" => restricted(form),
      "member_privacy" => if(form.target == "member", do: form.member_privacy, else: "hidden")
    }
  end

  defp restricted(%__MODULE__{target: "member"}), do: true
  defp restricted(%__MODULE__{target: "equipment"}), do: false
  defp restricted(%__MODULE__{restricted: restricted}), do: restricted

  @doc """
  The bundle the form names among the team's own `bundles` of its kind: `nil` for none,
  `{:existing, bundle}`, or `{:new, title}`.
  """
  def bundle(%__MODULE__{bundle: title}, _bundles) when title in [nil, ""], do: nil

  def bundle(%__MODULE__{bundle: title, target: target}, bundles) do
    wanted = String.downcase(title)

    case Enum.find(bundles, &own_bundle?(&1, target, wanted)) do
      nil -> {:new, title}
      bundle -> {:existing, bundle}
    end
  end

  defp own_bundle?(%CustomFieldBundle{} = bundle, target, wanted),
    do:
      bundle.owner_type == "Team" and bundle.target == target and
        String.downcase(bundle.title) == wanted
end
