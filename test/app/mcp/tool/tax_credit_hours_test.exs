defmodule App.MCP.Tool.TaxCreditHoursTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.TaxCreditHours

  @bounds {~U[2026-01-01 08:00:00Z], ~U[2027-01-01 08:00:00Z]}

  defp member(id, name, opts \\ []),
    do: %{id: id, name: name, joined_at: opts[:joined_at], left_at: opts[:left_at]}

  test "gives each member's hours as the letter counts them, and when their letter was made" do
    members = [member(2, "Sam"), member(1, "Alex")]
    hours = %{1 => %{primary_minutes: 600, secondary_minutes: 90, total_minutes: 690}}
    letters = %{1 => ~U[2027-01-10 05:30:00Z]}

    [alex, sam] = TaxCreditHours.build(members, hours, letters, @bounds, "America/Vancouver")

    assert alex["primary_hours"] == 10.0
    assert alex["secondary_hours"] == 1.5
    assert alex["total_hours"] == 11.5
    assert alex["letter_made_on"] == "2027-01-09"
    assert sam["total_hours"] == 0.0
    assert sam["letter_made_on"] == nil
  end

  test "leaves out a member who left before the year, unless they have hours" do
    gone = member(1, "Alex", left_at: ~U[2025-06-01 00:00:00Z])
    assert TaxCreditHours.build([gone], %{}, %{}, @bounds, "Etc/UTC") == []

    hours = %{1 => %{primary_minutes: 60, secondary_minutes: 0, total_minutes: 60}}
    assert [%{"member_id" => 1}] = TaxCreditHours.build([gone], hours, %{}, @bounds, "Etc/UTC")
  end
end
