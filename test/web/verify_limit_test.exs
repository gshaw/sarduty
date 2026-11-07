defmodule Web.VerifyLimitTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Event
  alias App.Model.MemberCard
  alias App.RateLimit
  alias Web.VerifyLimit

  @site_key "verify:site"
  @hour :timer.hours(1)

  test "records the miss that reaches the limit, once" do
    ip = "test-#{System.unique_integer([:positive])}"
    for _ <- 1..25, do: VerifyLimit.miss(ip, "ZZZZZZZZ")

    assert VerifyLimit.limited?(ip)
    assert %Event{ip: ^ip} = Event.get_last(:verify_limit_reached)

    assert Event.count_since(:verify_limit_reached, DateTime.add(DateTime.utc_now(), -1, :minute)) ==
             1
  end

  test "input that can't be a code never counts" do
    ip = "test-#{System.unique_integer([:positive])}"
    for _ <- 1..25, do: VerifyLimit.miss(ip, nil)

    refute VerifyLimit.limited?(ip)
  end

  describe "the site-wide alarm" do
    setup do
      on_exit(fn -> RateLimit.set(@site_key, @hour, 0) end)
      team = team_fixture()
      card = member_card_fixture(member_fixture(team))
      %{team: team, card: MemberCard.find_by_code(card.code)}
    end

    test "goes off at 500 misses across IPs, and never blocks an IP" do
      RateLimit.set(@site_key, @hour, 498)
      VerifyLimit.miss("test-#{System.unique_integer([:positive])}", "ZZZZZZZZ")
      refute VerifyLimit.alarm?()

      ip = "test-#{System.unique_integer([:positive])}"
      VerifyLimit.miss(ip, "ZZZZZZZZ")

      assert VerifyLimit.alarm?()
      assert Event.get_last(:verify_alarm)
      refute VerifyLimit.limited?(ip)
    end

    test "while it's up, records a card found from an IP that missed", %{team: team, card: card} do
      RateLimit.set(@site_key, @hour, 500)
      guesser = "test-#{System.unique_integer([:positive])}"
      VerifyLimit.miss(guesser, "ZZZZZZZZ")
      VerifyLimit.hit(guesser, card)

      assert %Event{ip: ^guesser, team_id: team_id, data: data} =
               Event.get_last(:verify_guess_found)

      assert team_id == team.id
      assert data["member_card_id"] == card.id
    end

    test "records no card found from an IP with no misses, or with the alarm down",
         %{card: card} do
      RateLimit.set(@site_key, @hour, 500)
      VerifyLimit.hit("test-#{System.unique_integer([:positive])}", card)

      RateLimit.set(@site_key, @hour, 0)
      ip = "test-#{System.unique_integer([:positive])}"
      VerifyLimit.miss(ip, "ZZZZZZZZ")
      VerifyLimit.hit(ip, card)

      refute Event.get_last(:verify_guess_found)
    end
  end
end
