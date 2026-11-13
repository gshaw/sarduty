defmodule App.Adapter.D4H.ParseTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.Parse

  # D4H keeps a member's join and leave dates and an award's dates as days (#1058).
  test "a day D4H keeps at 00:00 UTC is that date" do
    assert Parse.optional_day("2026-11-12T00:00:00.000Z") == ~D[2026-11-12]
    assert Parse.optional_day(nil) == nil
  end

  test "the start of a day on a Pacific team's clock goes to D4H as that day" do
    winter = Service.Convert.day_start(~D[2026-01-15], "America/Vancouver")
    summer = Service.Convert.day_start(~D[2026-07-15], "America/Vancouver")

    assert Parse.day_text(winter) == "2026-01-15T00:00:00Z"
    assert summer |> DateTime.to_iso8601() |> Parse.day_text() == "2026-07-15T00:00:00Z"
    assert Parse.day_text(nil) == nil
  end
end
