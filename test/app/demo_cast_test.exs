defmodule App.DemoCastTest do
  use ExUnit.Case, async: true

  alias App.CoastRange
  alias App.DemoCast
  alias App.Operation.BuildDemoTeam

  @now ~U[2026-11-03 19:00:00Z]
  @visitor %{name: "Morgan Visitor", email: "morgan@example.com"}

  defp rows, do: DemoCast.cast(@now, @visitor)["rows"]

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
    Enum.reduce(rows(), MapSet.new(["tag:Primary Hours", "tag:Secondary Hours"]), fn row, keys ->
      for key <- Map.values(row["refs"] || %{}) ++ (row["tags"] || []) do
        assert key in keys, "#{row["resource"]} points at #{key} before it is made"
      end

      if row["key"], do: MapSet.put(keys, row["key"]), else: keys
    end)
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
