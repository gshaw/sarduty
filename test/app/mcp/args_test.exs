defmodule App.MCP.ArgsTest do
  use ExUnit.Case, async: true

  alias App.MCP.Args

  @zone "America/Vancouver"

  test "a date range covers both days whole, in the team's time zone" do
    assert {:ok, ~D[2026-01-01], ~D[2026-03-31], start, finish} =
             Args.date_range(%{"from" => "2026-01-01", "to" => "2026-03-31"}, @zone)

    assert start == ~U[2026-01-01 08:00:00Z]
    # Daylight time by April 1, so 7 hours behind UTC.
    assert finish == ~U[2026-04-01 07:00:00Z]
  end

  test "a one-day range is that day" do
    assert {:ok, _from, _to, ~U[2026-07-01 07:00:00Z], ~U[2026-07-02 07:00:00Z]} =
             Args.date_range(%{"from" => "2026-07-01", "to" => "2026-07-01"}, @zone)
  end

  test "missing, malformed, or backwards dates say what to fix" do
    assert {:error, "Give from as a date" <> _} = Args.date_range(%{"to" => "2026-01-01"}, @zone)

    assert {:error, "Give to as a date" <> _} =
             Args.date_range(%{"from" => "2026-01-01", "to" => "March"}, @zone)

    assert {:error, "Give a from date on or before the to date."} =
             Args.date_range(%{"from" => "2026-02-01", "to" => "2026-01-01"}, @zone)
  end

  test "an optional string is trimmed, and blank is nil" do
    assert Args.optional_string(%{"tag" => " Rope "}, "tag") == "Rope"
    assert Args.optional_string(%{"tag" => "  "}, "tag") == nil
    assert Args.optional_string(%{"tag" => 3}, "tag") == nil
    assert Args.optional_string(%{}, "tag") == nil
  end

  test "an id is a whole number; a reference number, a string, or a wrong key is not" do
    assert Args.id(%{"activity_id" => 29_841}, "activity_id", "list_activities") ==
             {:ok, 29_841}

    message = "Give activity_id as a number, SAR Duty's id from list_activities."

    for args <- [%{"activity_id" => "02241"}, %{"activity" => 29_841}, %{}] do
      assert Args.id(args, "activity_id", "list_activities") == {:error, message}
    end
  end

  test "an optional id may be missing, but not wrong" do
    assert Args.optional_id(%{}, "member_id", "list_members") == {:ok, nil}
    assert Args.optional_id(%{"member_id" => 7}, "member_id", "list_members") == {:ok, 7}
    assert {:error, _} = Args.optional_id(%{"member_id" => "7"}, "member_id", "list_members")
  end
end
