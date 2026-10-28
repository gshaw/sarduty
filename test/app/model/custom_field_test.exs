defmodule App.Model.CustomFieldTest do
  use ExUnit.Case, async: true

  alias App.Model.CustomField

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
end
