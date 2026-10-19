defmodule App.Model.MemberTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Member

  test "takes whatever D4H holds, however long or odd" do
    # A D4H address field once held a paragraph of notes and broke a team's first refresh.
    member =
      member_fixture(team_fixture(), %{
        name: String.duplicate("n", 80),
        address: String.duplicate("a", 500),
        email: "not an email"
      })

    assert String.length(member.address) == 500
  end

  test "missing details are a mobile phone and an email, blank or not there" do
    assert Member.missing_details(%{phone: "604-555-0100", email: "a@example.com"}) == []
    assert Member.missing_details(%{phone: nil, email: ""}) == [:mobile_phone, :email]
    assert Member.missing_details(%{phone: "", email: "a@example.com"}) == [:mobile_phone]
  end

  test "looks like not a person with no email, no mobile phone, and no attendance" do
    bot = %Member{phone: nil, email: ""}

    assert Member.looks_like_not_a_person?(bot, false)
    refute Member.looks_like_not_a_person?(bot, true)
    refute Member.looks_like_not_a_person?(%{bot | not_a_person: true}, false)
    refute Member.looks_like_not_a_person?(%{bot | email: "a@example.com"}, false)
  end

  describe "not_seen_query/4" do
    @now ~U[2026-10-17 18:00:00Z]

    defp not_seen(team, days \\ 90) do
      Member
      |> Member.not_seen_query(team, days, @now)
      |> Repo.all()
      |> Enum.map(& &1.id)
      |> Enum.sort()
    end

    test "finds current members with no attendance in the time frame, and guesses at no bots" do
      team =
        team_fixture(%{d4h_access_key_member_id: 777, d4h_access_key_owner: "SAR Duty"})

      joined = ~U[2025-01-01 00:00:00Z]
      recent = activity_fixture(team, %{started_at: ~U[2026-09-01 18:00:00Z]})
      old = activity_fixture(team, %{started_at: ~U[2026-05-01 18:00:00Z]})

      seen = member_fixture(team, %{joined_at: joined})
      attendance_fixture(recent, seen)
      drifting = member_fixture(team, %{joined_at: joined})
      attendance_fixture(old, drifting)
      never = member_fixture(team, %{joined_at: joined})
      absent = member_fixture(team, %{joined_at: joined})
      attendance_fixture(recent, absent, %{status: "absent"})

      # Standing is a filter of its own now (#366), so the old guesses are gone.
      marked = member_fixture(team, %{joined_at: joined, not_a_person: true})
      key = member_fixture(team, %{joined_at: joined, d4h_member_id: 777})
      bot_like = member_fixture(team, %{joined_at: joined, email: nil, phone: nil})

      _new = member_fixture(team, %{joined_at: ~U[2026-09-01 00:00:00Z]})
      _left = member_fixture(team, %{joined_at: joined, left_at: ~U[2026-06-01 00:00:00Z]})
      _retired = member_fixture(team, %{joined_at: joined, d4h_status: "RETIRED"})
      _other_team = member_fixture(team_fixture(), %{joined_at: joined})

      assert not_seen(team) ==
               Enum.sort([drifting.id, never.id, absent.id, marked.id, key.id, bot_like.id])

      assert not_seen(team, 365) ==
               Enum.sort([never.id, absent.id, marked.id, key.id, bot_like.id])
    end

    test "the clock restarts at a check-in and at the end of an away period (#366)" do
      team = team_fixture()
      joined = ~U[2025-01-01 00:00:00Z]

      checked_in = member_fixture(team, %{joined_at: joined})

      Repo.insert!(%App.Model.MemberCheckIn{
        team_id: team.id,
        member_id: checked_in.id,
        checked_in_on: ~D[2026-09-20]
      })

      old_check_in = member_fixture(team, %{joined_at: joined})

      Repo.insert!(%App.Model.MemberCheckIn{
        team_id: team.id,
        member_id: old_check_in.id,
        checked_in_on: ~D[2026-03-01]
      })

      back = member_fixture(team, %{joined_at: joined})
      away_period_fixture(back, ~D[2026-02-01], ~D[2026-09-01])
      away_now = member_fixture(team, %{joined_at: joined})
      away_period_fixture(away_now, ~D[2026-10-01], ~D[2027-01-01])
      leaving_soon = member_fixture(team, %{joined_at: joined})
      away_period_fixture(leaving_soon, ~D[2026-11-01], ~D[2027-01-01])

      other_team_check_in = member_fixture(team, %{joined_at: joined})
      other_team = team_fixture()

      Repo.insert!(%App.Model.MemberCheckIn{
        team_id: other_team.id,
        member_id: other_team_check_in.id,
        checked_in_on: ~D[2026-10-01]
      })

      assert not_seen(team) ==
               Enum.sort([old_check_in.id, leaving_soon.id, other_team_check_in.id])
    end

    test "a sign-up for a coming activity isn't being seen (#364)" do
      team = team_fixture()
      signed_up = member_fixture(team, %{joined_at: ~U[2025-01-01 00:00:00Z]})
      coming = activity_fixture(team, %{started_at: DateTime.add(@now, 7, :day)})
      attendance_fixture(coming, signed_up, %{started_at: coming.started_at})

      assert not_seen(team) == [signed_up.id]
      assert Member.last_attended_at(signed_up, @now) == nil
    end

    test "a day back from leave counts the same as a check-in that day" do
      team = team_fixture()
      joined = ~U[2025-01-01 00:00:00Z]
      # 90 days before @now is July 19 on the team's clock.
      checked_in = member_fixture(team, %{joined_at: joined})

      Repo.insert!(%App.Model.MemberCheckIn{
        team_id: team.id,
        member_id: checked_in.id,
        checked_in_on: ~D[2026-07-19]
      })

      back_that_day = member_fixture(team, %{joined_at: joined})
      away_period_fixture(back_that_day, ~D[2026-06-01], ~D[2026-07-18])
      back_the_day_before = member_fixture(team, %{joined_at: joined})
      away_period_fixture(back_the_day_before, ~D[2026-06-01], ~D[2026-07-17])

      assert not_seen(team) == [back_the_day_before.id]
    end
  end

  describe "clock_start/2" do
    defp row(attrs) do
      Map.merge(
        %{
          last_attended_at: nil,
          checked_in_on: nil,
          away_ends_on: nil,
          member: %{joined_at: ~U[2024-06-01 19:00:00Z]}
        },
        attrs
      )
    end

    test "counts from the latest of last attended, check-in, back from leave, and joined" do
      tz = "America/Vancouver"
      clock = &(&1 |> row() |> Member.clock_start(tz))
      assert clock.(%{}) == {:joined, ~D[2024-06-01]}
      assert clock.(%{last_attended_at: ~U[2026-05-15 02:00:00Z]}) == {:attended, ~D[2026-05-14]}

      assert clock.(%{last_attended_at: ~U[2026-05-15 02:00:00Z], away_ends_on: ~D[2026-09-01]}) ==
               {:back, ~D[2026-09-02]}

      assert clock.(%{away_ends_on: ~D[2026-09-01], checked_in_on: ~D[2026-10-03]}) ==
               {:checked_in, ~D[2026-10-03]}
    end
  end
end
