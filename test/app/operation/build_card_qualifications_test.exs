defmodule App.Operation.BuildCardQualificationsTest do
  use ExUnit.Case, async: true

  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.Operation.BuildCardQualifications

  @now ~U[2026-09-30 12:00:00Z]

  defp endorsement(name, ids) do
    %Endorsement{
      name: name,
      endorsement_qualifications:
        Enum.map(ids, &%EndorsementQualification{d4h_qualification_id: &1})
    }
  end

  defp award(id, starts_at, ends_at),
    do: %{d4h_qualification_id: id, starts_at: starts_at, ends_at: ends_at}

  test "an endorsement is current until the latest end among its active awards" do
    awards = [
      award(1, ~U[2025-01-01 00:00:00Z], ~U[2026-11-15 00:00:00Z]),
      award(2, ~U[2025-06-01 00:00:00Z], ~U[2027-05-01 00:00:00Z])
    ]

    assert [%{name: "First Aid", ends_at: ~U[2027-05-01 00:00:00Z]}] =
             BuildCardQualifications.summarize([endorsement("First Aid", [1, 2])], awards, @now)
  end

  test "an award with no end means no expiry" do
    awards = [award(1, nil, ~U[2027-01-01 00:00:00Z]), award(2, nil, nil)]

    assert [%{name: "Tracking", ends_at: nil}] =
             BuildCardQualifications.summarize([endorsement("Tracking", [1, 2])], awards, @now)
  end

  test "expired, future, and missing awards leave the endorsement off" do
    awards = [
      award(1, nil, ~U[2026-01-01 00:00:00Z]),
      award(2, ~U[2027-01-01 00:00:00Z], nil)
    ]

    assert [] = BuildCardQualifications.summarize([endorsement("Rope", [1, 2, 3])], awards, @now)
  end

  test "only the highest tier shows: a stricter endorsement hides the one it implies" do
    basic = endorsement("First Aid (7 hours or higher)", [7, 16, 70])
    advanced = endorsement("First Aid (70 hours or higher)", [70])
    rope = endorsement("Rope", [3])

    assert [%{name: "First Aid (70 hours or higher)"}, %{name: "Rope"}] =
             BuildCardQualifications.summarize(
               [basic, advanced, rope],
               [award(70, nil, nil), award(3, nil, nil)],
               @now
             )

    assert [%{name: "First Aid (7 hours or higher)"}] =
             BuildCardQualifications.summarize([basic, advanced], [award(16, nil, nil)], @now)
  end

  test "endorsements with the same qualifications both show" do
    awards = [award(1, nil, nil)]
    both = [endorsement("CRC", [1]), endorsement("Criminal Record Check", [1])]

    assert [%{name: "CRC"}, %{name: "Criminal Record Check"}] =
             BuildCardQualifications.summarize(both, awards, @now)
  end

  test "describe gives one line per qualification in the team's time zone" do
    tz = "America/Vancouver"

    assert BuildCardQualifications.describe(
             %{name: "First Aid", ends_at: ~U[2026-11-15 07:00:00Z]},
             tz
           ) == "First Aid — expires Nov 2026"

    assert BuildCardQualifications.describe(
             %{name: "Tracking", ends_at: nil},
             tz
           ) ==
             "Tracking — no expiry"
  end
end
