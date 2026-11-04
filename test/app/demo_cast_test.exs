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

    assert %{"permission" => "OWNER", "email" => "morgan@example.com"} =
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
    |> DemoCast.local_rows()
    |> Enum.reduce(MapSet.new(), fn {kind, key, _row, links}, local ->
      for {_field, ref} <- links do
        assert DemoCast.key(ref) in keys or ref in local,
               "#{kind} #{inspect(key)} → #{inspect(ref)}"
      end

      MapSet.put(local, {kind, key})
    end)
  end
end
