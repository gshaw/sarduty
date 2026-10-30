defmodule Web.Components.ColumnsTest do
  use ExUnit.Case, async: true

  alias Web.Components.Columns

  @now ~U[2026-10-29 18:00:00Z]

  defp expiry_in(amount, unit), do: @now |> DateTime.add(amount, unit) |> Columns.expiry(@now)

  test "expiry: past is expired, within 60 days counts the days left, later is nothing" do
    assert Columns.expiry(nil, @now) == nil
    assert expiry_in(-1, :second) == :expired
    assert expiry_in(0, :second) == :expired
    assert expiry_in(3, :hour) == 1
    assert expiry_in(60, :day) == 60
    assert expiry_in(61, :day) == nil
  end
end
