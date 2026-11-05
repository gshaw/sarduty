defmodule App.Operation.MakeTransferTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.QualificationAward
  alias App.Operation.MakeTransfer

  defp award(id, d4h_award_id, title),
    do: %{id: id, d4h_award_id: d4h_award_id, qualification: %{title: title}}

  defp d4h(d4h_award_id, starts_at, ends_at),
    do: %QualificationAward{d4h_award_id: d4h_award_id, starts_at: starts_at, ends_at: ends_at}

  describe "plan/2" do
    test "keeps the picked order and takes D4H's dates now" do
      first_aid = award(1, 101, "First aid")
      gsar = award(2, 102, "Ground search and rescue")

      d4h_awards = [
        d4h(102, ~U[2020-11-04 00:00:00Z], nil),
        d4h(101, ~U[2026-07-30 00:00:00Z], ~U[2029-07-30 00:00:00Z]),
        d4h(999, ~U[2021-01-01 00:00:00Z], nil)
      ]

      assert {:ok, [one, two]} = MakeTransfer.plan([first_aid, gsar], d4h_awards)
      assert %{position: 1, award: ^first_aid, d4h: %{ends_at: ~U[2029-07-30 00:00:00Z]}} = one
      assert %{position: 2, award: ^gsar, d4h: %{starts_at: ~U[2020-11-04 00:00:00Z]}} = two
    end

    test "an award D4H no longer has stops it, named" do
      picked = [award(1, 101, "First aid"), award(2, 102, "Swiftwater rescue technician")]

      assert MakeTransfer.plan(picked, [d4h(101, nil, nil)]) ==
               {:error, {:changed, "Swiftwater rescue technician"}}
    end
  end

  describe "picked/2" do
    test "only the offered awards, in the rows' order, whatever the ids' type" do
      rows = [%{award: award(1, 101, "A")}, %{award: award(2, 102, "B")}]

      picked = MakeTransfer.picked(rows, ["2", 1, "99"])
      assert Enum.map(picked, & &1.id) == [1, 2]
      assert MakeTransfer.picked(rows, []) == []
    end
  end
end
