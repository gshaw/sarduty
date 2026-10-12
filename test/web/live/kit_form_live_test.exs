defmodule Web.KitFormLiveTest do
  use ExUnit.Case, async: true

  alias App.Model.Tag
  alias Web.KitFormLive

  defp tags(titles),
    do: titles |> Enum.with_index() |> Enum.map(fn {t, i} -> %Tag{id: i, title: t} end)

  test "with no search, the most used tags the kit lacks, at most 8" do
    all = tags(~w(A B C D E F G H I J K))
    uses = ~w(A B C D E F G H I J) |> Enum.with_index() |> Map.new(fn {t, i} -> {t, 20 - i} end)
    chosen = [Enum.at(all, 0)]

    result = KitFormLive.tag_results(all, chosen, "", uses)

    assert Enum.map(result.tags, & &1.title) == ~w(B C D E F G H I)
    assert result.more == 0
  end

  test "an unused tag isn't offered until searched for" do
    all = tags(["Avalanche", "Boat"])

    assert KitFormLive.tag_results(all, [], "", %{"Avalanche" => 1}).tags
           |> Enum.map(& &1.title) == ["Avalanche"]

    assert KitFormLive.tag_results(all, [], " BOA ", %{}).tags |> Enum.map(& &1.title) ==
             ["Boat"]
  end

  test "a search shows 10 matches and counts the rest" do
    all = tags(for i <- 10..24, do: "Water #{i}")

    result = KitFormLive.tag_results(all, [], "water", %{})

    assert length(result.tags) == 10
    assert result.more == 5
  end
end
