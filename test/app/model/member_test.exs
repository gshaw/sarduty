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

    test "finds current people with no attendance in the time frame, leaving out bots" do
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

      _new = member_fixture(team, %{joined_at: ~U[2026-09-01 00:00:00Z]})
      _left = member_fixture(team, %{joined_at: joined, left_at: ~U[2026-06-01 00:00:00Z]})
      _retired = member_fixture(team, %{joined_at: joined, d4h_status: "RETIRED"})
      _marked = member_fixture(team, %{joined_at: joined, not_a_person: true})
      _key = member_fixture(team, %{joined_at: joined, d4h_member_id: 777})
      _bot_like = member_fixture(team, %{joined_at: joined, email: nil, phone: nil})
      _other_team = member_fixture(team_fixture(), %{joined_at: joined})

      assert not_seen(team) == Enum.sort([drifting.id, never.id, absent.id])
      assert not_seen(team, 365) == Enum.sort([never.id, absent.id])
    end
  end
end
