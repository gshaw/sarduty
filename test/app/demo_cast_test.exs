defmodule App.DemoCastTest do
  use ExUnit.Case, async: true

  alias App.CoastRange
  alias App.DemoCast
  alias App.Model.CustomField
  alias App.Operation.BuildDemoTeam

  @now ~U[2026-11-03 19:00:00Z]
  @visitor %{name: "Morgan Visitor", email: "morgan@example.com"}

  defp rows, do: DemoCast.cast(@now, @visitor)["rows"]

  # What Records answers Coast Range's cast for its fields and their options: made-up ids.
  defp organization do
    keys =
      for %{"resource" => "custom-fields"} = row <- rows(),
          key <- [row["key"] | row["optionKeys"]],
          do: key

    ids = keys |> Enum.with_index(1) |> Map.new(fn {key, i} -> {key, 500 + i} end)
    %{id: 2_000_000_000, ids: ids}
  end

  defp silver_basin, do: DemoCast.silver_basin(@now, organization())

  test "a demo copies every feature Coast Range SAR turns on" do
    [{:team, :coastrange, team, []} | _rows] = CoastRange.build(@now)

    switches =
      for {key, true} <- Map.from_struct(team),
          name = to_string(key),
          name == "member_logins" or String.ends_with?(name, "_enabled"),
          do: key

    assert switches -- BuildDemoTeam.settings() == []
  end

  test "every row points only at rows before it, or at the hours tags Records has" do
    for rows <- [rows(), silver_basin()["rows"]] do
      Enum.reduce(rows, MapSet.new(["tag:Primary Hours", "tag:Secondary Hours"]), fn row, keys ->
        fields = row["fields"] || %{}

        options =
          for {_field, value} <- fields, is_list(value), key <- value, do: key

        for key <-
              Map.values(row["refs"] || %{}) ++ (row["tags"] || []) ++ Map.keys(fields) ++ options do
          assert key in keys, "#{row["resource"]} points at #{key} before it is made"
        end

        if row["key"],
          do: keys |> MapSet.put(row["key"]) |> MapSet.union(MapSet.new(row["optionKeys"] || [])),
          else: keys
      end)
    end
  end

  # Records is the test bed (#1003): a Records team has every field D4H gives one.
  test "every field, option, and value in Coast Range reaches the cast" do
    build = CoastRange.build(@now, visitor: @visitor)
    sent = for %{"resource" => "custom-fields"} = row <- rows(), into: %{}, do: {row["key"], row}
    fields = for {:custom_field, id, field, []} <- build, do: {id, field}
    assert map_size(sent) == length(fields)

    for {id, field} <- fields do
      row = sent[DemoCast.key({:custom_field, id})]
      options = Enum.sort_by(field.options, & &1["ordering"])

      assert row["body"]["title"] == field.title
      assert row["body"]["type"] == String.upcase(field.field_type)
      assert row["body"]["mandatory"] == field.required

      assert row["body"]["restricted"] ==
               if(field.restricted, do: "RESTRICTED", else: "UNRESTRICTED")

      assert Enum.map(row["body"]["options"] || [], & &1["label"]) ==
               Enum.map(options, & &1["label"])

      assert row["optionKeys"] ==
               Enum.map(options, &DemoCast.key({:custom_field_option, &1["id"]}))

      assert row["owner"] == if(CustomField.organisation?(field), do: "organization")
    end

    by_key = Map.new(rows(), &{&1["key"], &1})

    values =
      for {kind, key, %{custom_values: %{} = values}, _links} <- build,
          kind in [:member, :activity, :equipment_item],
          values != %{},
          do: {DemoCast.key({kind, key}), values}

    assert length(values) > 30

    for {key, values} <- values do
      expected =
        Map.new(values, fn
          {id, ids} when is_list(ids) ->
            {"custom_field:#{id}", Enum.map(ids, &"custom_field_option:#{&1}")}

          {id, text} ->
            {"custom_field:#{id}", text}
        end)

      assert by_key[key]["fields"] == expected, key
    end
  end

  test "the first cast makes WESARA, and Silver Basin's joins it with values by Records' ids" do
    assert DemoCast.cast(@now, @visitor)["team"]["organization"] == %{"title" => "WESARA"}

    %{id: id, ids: ids} = organization()
    cast = silver_basin()
    assert cast["team"]["organizationId"] == id
    refute Enum.any?(cast["rows"], &(&1["resource"] == "custom-fields"))

    incidents = for %{"resource" => "incidents"} = row <- cast["rows"], do: row
    assert length(incidents) == 4

    for incident <- incidents do
      refute incident["fields"]
      values = incident["body"]["customFieldValues"]
      assert length(values) == 20
      assert Enum.all?(values, &(&1["id"] in Map.values(ids)))

      for %{"value" => value} <- values,
          is_list(value),
          do: assert(Enum.all?(value, &(&1 in Map.values(ids))))
    end
  end

  test "equipment carries D4H's costs in whole cents, a kind's when its items share them" do
    by_title = fn resource, field ->
      for %{"resource" => ^resource, "body" => body} <- rows(), into: %{}, do: {body[field], body}
    end

    kinds = by_title.("equipment-kinds", "title")
    items = by_title.("equipment", "ref")

    assert %{"costPerDistance" => 67, "costPerHour" => 0, "costPerUse" => 0} = kinds["Truck"]
    assert %{"costPerDistance" => 67} = items["Truck 1"]
    assert items["Radio 1"]["costPerHour"] == 1500
    refute Map.has_key?(kinds["Radio"], "costPerHour")
    refute Map.has_key?(items["Radio 2"], "costPerHour")
    assert kinds["Throw bag"]["costPerUse"] == 2500
  end

  test "a template's field values follow Records' ids" do
    %{ids: ids} = organization()

    [callout] =
      for {:template, "Callout", template, _links} <- DemoCast.local_rows(@now, @visitor),
          do: template

    assert map_size(callout.custom_values) == 4
    values = DemoCast.local_values(callout.custom_values, ids)
    answered = Map.values(ids)
    assert values |> Map.keys() |> Enum.all?(&(String.to_integer(&1) in answered))
    assert values |> Map.values() |> List.flatten() |> Enum.all?(&(&1 in answered))
  end

  test "Silver Basin SAR is the second team, with its own five members (#963)" do
    cast = silver_basin()
    assert cast["team"]["title"] == "Silver Basin SAR"
    members = for %{"resource" => "members", "body" => body} <- cast["rows"], do: body["name"]
    assert members == App.SilverBasin.names()
  end

  test "the visitor joins as an Owner beside Alex Chen, who stays" do
    members = for %{"resource" => "members", "body" => body} <- rows(), do: body

    assert %{"permission" => 0, "email" => "morgan@example.com"} =
             Enum.find(members, &(&1["name"] == "Morgan Visitor"))

    assert %{"permission" => 0} = Enum.find(members, &(&1["name"] == "Alex Chen"))
    assert length(members) == length(App.CoastRange.names()) + 1
  end

  test "the hours tags are left to Records, and the activities are tagged by key" do
    tags = for %{"resource" => "tags", "body" => %{"title" => title}} <- rows(), do: title
    refute "Primary Hours" in tags

    incident = Enum.find(rows(), &(&1["body"]["referenceDescription"] == "Missing hunter"))
    assert incident["tags"] == ["tag:Primary Hours", "tag:Secondary Hours"]
  end

  test "SAR Duty's own rows link only to rows the cast or they make" do
    keys = MapSet.new(rows(), & &1["key"])

    @now
    |> DemoCast.local_rows(@visitor)
    |> Enum.reduce(MapSet.new(), fn {kind, key, _row, links}, local ->
      for {_field, ref} <- links do
        assert ref in local or DemoCast.key(ref) in keys,
               "#{kind} #{inspect(key)} → #{inspect(ref)}"
      end

      MapSet.put(local, {kind, key})
    end)
  end

  test "the visitor has no stranger's photo, and their rows point at them by key" do
    visitor = Enum.find(rows(), &(&1["key"] == "member:visitor"))
    refute Map.has_key?(visitor, "photo")

    assert Enum.any?(
             rows(),
             &(&1["resource"] == "attendance" and &1["refs"]["memberId"] == "member:visitor")
           )
  end

  test "each trip names an attendance row Records answers an id for" do
    keys = MapSet.new(rows(), & &1["key"])

    trips = for {:trip, _key, trip, _links} <- DemoCast.local_rows(@now, @visitor), do: trip
    assert trips != []

    for trip <- trips,
        do: assert(DemoCast.key({:attendance, trip.d4h_attendance_id}) in keys)
  end
end
