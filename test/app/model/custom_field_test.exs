defmodule App.Model.CustomFieldTest do
  use ExUnit.Case, async: true

  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle

  @tz "America/Vancouver"

  defp field(attrs), do: struct(%CustomField{field_type: "text", options: []}, attrs)

  test "a choice shows its option labels, and an unknown option its id" do
    city =
      field(%{
        field_type: "multiple_choice",
        options: [%{"id" => 1, "label" => "Surrey"}, %{"id" => 2, "label" => "Delta"}]
      })

    assert CustomField.display(city, [1, 2], @tz) == "Surrey, Delta"
    assert CustomField.display(city, [9], @tz) == "Option 9"
  end

  defp show(attrs, value), do: attrs |> field() |> CustomField.display(value, @tz)

  test "dates and times are formatted; anything else shows as it came" do
    assert show(%{field_type: "date"}, "2026-10-28") == "Oct 28, 2026"
    assert show(%{field_type: "date"}, "soon") == "soon"
    assert show(%{field_type: "number"}, "3") == "3"
    assert show(%{value_units: "km"}, "12") == "12 km"
  end

  test "describes values by field title, for history" do
    index = %{
      "888" =>
        field(%{
          title: "City",
          field_type: "single_choice",
          options: [%{"id" => 1, "label" => "Surrey"}]
        })
    }

    assert CustomField.describe_values(index, %{"888" => [1], "5" => "x"}, ["888", "5", "6"], @tz) ==
             %{"City" => "Surrey", "Field 5" => ~s("x"), "Field 6" => nil}
  end

  test "rows: a restricted member field shows like any other (#1056)" do
    birth = field(%{d4h_custom_field_id: 1, target: "member", restricted: true})
    notes = field(%{d4h_custom_field_id: 2, target: "equipment", restricted: true})
    values = %{"1" => "1988", "2" => "Serviced"}

    assert [%{field: ^birth, text: "1988"}] = CustomField.rows([birth, notes], values, @tz)
  end

  test "rows: values in order, required ones missing on request, restricted ones on request" do
    city = field(%{d4h_custom_field_id: 1, title: "City", restricted: true})
    area = field(%{d4h_custom_field_id: 2, title: "Area", required: true})
    notes = field(%{d4h_custom_field_id: 3, title: "Notes"})
    values = %{"1" => "Surrey", "3" => "Found"}

    fields = [city, area, notes]
    titles = &Enum.map(&1, fn row -> {row.field.title, row.text, row.missing?} end)

    assert fields |> CustomField.rows(values, @tz) |> titles.() == [{"Notes", "Found", false}]

    assert fields |> CustomField.rows(values, @tz, restricted: true, missing: true) |> titles.() ==
             [{"City", "Surrey", false}, {"Area", nil, true}, {"Notes", "Found", false}]

    assert CustomField.rows([notes], nil, @tz) == []
  end

  defp bundle(id, attrs),
    do:
      struct(
        %CustomFieldBundle{
          d4h_bundle_id: id,
          title: "Bundle #{id}",
          owner_type: "Organisation",
          owner_id: 7
        },
        attrs
      )

  test "grouped: fields in no bundle first, then bundles by ordering and id, each in order (#872)" do
    kms = bundle(43, %{title: "KMS Data"})
    disasters = bundle(179, %{title: "Natural disasters"})
    assistance = bundle(199, %{title: "Assistance Provided"})

    fields = [
      field(%{title: "Tasked to do", bundle: assistance}),
      field(%{title: "City", bundle: nil}),
      field(%{title: "SAR Severity", bundle: kms}),
      field(%{title: "Evacuations", bundle: disasters}),
      field(%{title: "Agency", bundle: nil}),
      field(%{title: "Activity", bundle: kms})
    ]

    titles = fn groups ->
      Enum.map(groups, fn {bundle, fields} ->
        {bundle && bundle.title, Enum.map(fields, & &1.title)}
      end)
    end

    assert fields |> CustomField.grouped() |> titles.() == [
             {nil, ["City", "Agency"]},
             {"KMS Data", ["SAR Severity", "Activity"]},
             {"Natural disasters", ["Evacuations"]},
             {"Assistance Provided", ["Tasked to do"]}
           ]

    late = bundle(1, %{title: "Late", ordering: 2})
    early = bundle(500, %{title: "Early", ordering: 0})
    reordered = [field(%{title: "X", bundle: late}), field(%{title: "Y", bundle: early})]

    assert reordered |> CustomField.grouped() |> titles.() == [{"Early", ["Y"]}, {"Late", ["X"]}]
    assert CustomField.grouped([]) == []
  end

  test "grouped: rows by their field, and one bundle from several teams' copies stays one group" do
    one_team = bundle(43, %{id: 1})
    other_team = bundle(43, %{id: 2})

    rows = [
      %{field: field(%{title: "A", bundle: one_team})},
      %{field: field(%{title: "B", bundle: other_team})}
    ]

    assert [{%{d4h_bundle_id: 43}, [_a, _b]}] = CustomField.grouped(rows, & &1.field)
  end

  test "merge_copies: an organization's field once, with every choice its teams added" do
    option = fn id, owner ->
      %{"id" => id, "label" => "#{id}", "owner_type" => "Team", "owner_id" => owner}
    end

    copy = fn team_id, options ->
      field(%{
        id: team_id,
        team_id: team_id,
        d4h_custom_field_id: 5,
        title: "Agency",
        owner_type: "Organisation",
        owner_id: 7,
        options: options
      })
    end

    assert [agency] =
             CustomField.merge_copies([
               copy.(1, [option.(1, nil), option.(2, 11)]),
               copy.(2, [option.(1, nil), option.(3, 12)])
             ])

    assert Enum.map(agency.options, & &1["id"]) == [1, 2, 3]
  end

  test "by_target: in the Fields pages' order, leaving out targets with none" do
    fields = [
      field(%{target: "member"}),
      field(%{target: "incident"}),
      field(%{target: "member"})
    ]

    assert fields
           |> CustomField.by_target()
           |> Enum.map(fn {target, fields} -> {target, length(fields)} end) ==
             [{"incident", 1}, {"member", 2}]
  end
end
