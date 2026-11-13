defmodule App.Adapter.D4H.QualificationAwardTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.QualificationAward

  # D4H keeps an award's dates as the day at 00:00 UTC (#1058).
  test "an award's start and end are D4H's days, not the evening before" do
    award =
      QualificationAward.build(%{
        "id" => 1,
        "member" => %{"resourceType" => "Member", "id" => 2},
        "qualification" => %{"id" => 3},
        "startsAt" => "2026-11-12T00:00:00.000Z",
        "endsAt" => "2031-11-12T00:00:00.000Z"
      })

    assert award.starts_on == ~D[2026-11-12]
    assert award.ends_on == ~D[2031-11-12]
  end

  test "an award with no end has no end day" do
    award =
      QualificationAward.build(%{
        "member" => %{"resourceType" => "Member", "id" => 2},
        "qualification" => %{"id" => 3},
        "startsAt" => "2026-11-12T00:00:00.000Z",
        "endsAt" => nil
      })

    assert award.ends_on == nil
  end

  test "an award starts on its day" do
    award = %QualificationAward{starts_on: ~D[2026-10-18]}

    assert QualificationAward.starts_on?(award, ~D[2026-10-18])
    refute QualificationAward.starts_on?(award, ~D[2026-10-17])
  end

  test "an award with no start starts on no day" do
    refute QualificationAward.starts_on?(%QualificationAward{starts_on: nil}, ~D[2026-10-18])
  end
end
