defmodule App.ViewModel.CustomFieldFormViewModelTest do
  use ExUnit.Case, async: true

  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle
  alias App.ViewModel.CustomFieldFormViewModel

  defp field(attrs),
    do:
      struct(
        %CustomField{field_type: "text", options: [], owner_type: "Team", bundle: nil},
        attrs
      )

  # The team's fields and its organization's.
  @fields [
    %CustomField{id: 1, target: "incident", title: "Agency", owner_type: "Organisation"},
    %CustomField{
      id: 2,
      target: "incident",
      title: "Team notes",
      field_type: "text",
      owner_type: "Team",
      bundle: nil
    },
    %CustomField{
      id: 3,
      target: "incident",
      title: "Old",
      owner_type: "Team",
      archived_at: ~U[2026-01-01 00:00:00Z]
    },
    %CustomField{id: 4, target: "member", title: "Call sign", owner_type: "Team"}
  ]

  defp add(params, target \\ "incident"),
    do:
      target
      |> CustomFieldFormViewModel.new()
      |> CustomFieldFormViewModel.changeset(params, @fields)

  defp errors(changeset),
    do: for({key, {message, _}} <- changeset.errors, do: {key, message})

  test "a name is 1 to 150 characters with no |" do
    assert {:title, "Enter a name."} in errors(add(%{"title" => " ", "field_type" => "text"}))

    long = String.duplicate("a", 151)

    assert {:title, "Enter a name of 150 characters or fewer."} in errors(
             add(%{"title" => long, "field_type" => "text"})
           )

    assert {:title, "Enter a name without a | in it."} in errors(
             add(%{"title" => "A|B", "field_type" => "text"})
           )
  end

  test "a name no other live field of the kind has, the team's or its organization's" do
    taken = "Enter a name no other field on incidents has."
    assert {:title, taken} in errors(add(%{"title" => " agency ", "field_type" => "text"}))
    assert {:title, taken} in errors(add(%{"title" => "Team Notes", "field_type" => "text"}))

    # An archived field's, or another kind's, is free.
    assert add(%{"title" => "Old", "field_type" => "text"}).valid?
    assert add(%{"title" => "Call sign", "field_type" => "text"}).valid?

    # A field keeps its own name when it changes.
    team_notes = Enum.at(@fields, 1)

    assert team_notes
           |> CustomFieldFormViewModel.from_field()
           |> CustomFieldFormViewModel.changeset(%{"title" => "Team notes"}, @fields, team_notes)
           |> Map.get(:valid?)
  end

  test "a type from D4H's list, and a choice field has a live choice, each named once" do
    assert {:field_type, "Select a type."} in errors(add(%{"title" => "A", "field_type" => "x"}))

    choice = %{"title" => "Debrief held", "field_type" => "single_choice"}
    assert {:choices, "Enter at least 1 choice."} in errors(add(choice))

    assert {:choices, "Enter each choice once."} in errors(
             add(Map.put(choice, "choices", ["Yes", "yes"]))
           )

    assert {:choices, "Enter a name for each choice."} in errors(
             add(
               Map.put(choice, "choices", %{"0" => %{"label" => "Yes"}, "1" => %{"label" => ""}})
             )
           )

    assert add(Map.put(choice, "choices", ["Yes", "No"])).valid?
  end

  test "choices come from the form in its order, or as a list of labels" do
    changeset =
      add(%{
        "title" => "Debrief held",
        "field_type" => "multiple_choice",
        "choices" => %{
          "1" => %{"id" => "44", "label" => " No ", "archived" => "true"},
          "0" => %{"id" => "", "label" => "Yes"}
        }
      })

    assert Ecto.Changeset.get_field(changeset, :choices) == [
             %{"id" => nil, "label" => "Yes", "archived" => false},
             %{"id" => 44, "label" => "No", "archived" => true}
           ]
  end

  test "units are up to 10 characters" do
    params = %{"title" => "Distance", "field_type" => "number", "value_units" => "kilometres!"}
    assert {:value_units, "Enter units of 10 characters or fewer."} in errors(add(params))
  end

  test "a change never takes a new kind or type" do
    debrief = field(%{id: 9, target: "incident", title: "Debrief", field_type: "text"})

    changeset =
      debrief
      |> CustomFieldFormViewModel.from_field()
      |> CustomFieldFormViewModel.changeset(
        %{"target" => "member", "field_type" => "number"},
        @fields,
        debrief
      )

    assert Ecto.Changeset.get_field(changeset, :target) == "incident"
    assert Ecto.Changeset.get_field(changeset, :field_type) == "text"
  end

  test "Needed to publish on activities only, and Restricted set for the kind (2026-11-13)" do
    value = fn target, attrs ->
      target
      |> CustomFieldFormViewModel.new()
      |> Map.merge(attrs)
      |> CustomFieldFormViewModel.value()
    end

    attrs = %{title: "A", field_type: "text", required: true, restricted: true}

    assert %{"required" => true, "restricted" => true} = value.("incident", attrs)

    assert %{"required" => true, "restricted" => false} =
             value.("event", %{attrs | restricted: false})

    # A member field is RESTRICTED, safer inside D4H; an equipment field UNRESTRICTED.
    assert %{"required" => false, "restricted" => true} =
             value.("member", %{attrs | restricted: false})

    assert %{"required" => false, "restricted" => false} = value.("equipment", attrs)
  end

  test "a new member field starts hidden from members, and privacy is a member field's only" do
    assert CustomFieldFormViewModel.new("member").member_privacy == "hidden"

    assert %{"member_privacy" => "editable"} =
             "member"
             |> CustomFieldFormViewModel.new()
             |> Map.put(:member_privacy, "editable")
             |> CustomFieldFormViewModel.value()

    assert %{"member_privacy" => "hidden"} =
             "incident"
             |> CustomFieldFormViewModel.new()
             |> Map.put(:member_privacy, "editable")
             |> CustomFieldFormViewModel.value()
  end

  test "units go on a number only" do
    form = %{CustomFieldFormViewModel.new("incident") | field_type: "text", value_units: "km"}
    assert CustomFieldFormViewModel.value(form)["value_units"] == nil
    assert CustomFieldFormViewModel.value(%{form | field_type: "number"})["value_units"] == "km"
  end

  test "a bundle is one of the team's own for the kind, or a new name" do
    bundles = [
      %CustomFieldBundle{
        d4h_bundle_id: 5,
        title: "KMS Data",
        target: "incident",
        owner_type: "Organisation"
      },
      %CustomFieldBundle{
        d4h_bundle_id: 6,
        title: "Debrief",
        target: "incident",
        owner_type: "Team"
      },
      %CustomFieldBundle{d4h_bundle_id: 7, title: "Radio", target: "member", owner_type: "Team"}
    ]

    form = CustomFieldFormViewModel.new("incident")
    assert CustomFieldFormViewModel.bundle(%{form | bundle: nil}, bundles) == nil

    assert {:existing, %{d4h_bundle_id: 6}} =
             CustomFieldFormViewModel.bundle(%{form | bundle: "debrief"}, bundles)

    # The organization's, or another kind's, is never the team's to add to.
    assert CustomFieldFormViewModel.bundle(%{form | bundle: "KMS Data"}, bundles) ==
             {:new, "KMS Data"}

    assert CustomFieldFormViewModel.bundle(%{form | bundle: "Radio"}, bundles) == {:new, "Radio"}
  end
end
