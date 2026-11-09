defmodule App.Model.MemberCardTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team

  @now ~U[2026-09-30 12:00:00Z]

  test "only Coast Range SAR's sample cards start with SAMP (#854)" do
    assert Enum.all?(App.CoastRange.sample_cards(), &MemberCard.sample_code?(&1.code))

    assert Enum.all?(
             App.CoastRange.sample_cards(),
             &(MemberCard.normalize_code(&1.code) == &1.code)
           )

    refute MemberCard.sample_code?("K7Q4M2XA9H")
  end

  test "generate_code makes 10 characters that normalize to themselves" do
    for _ <- 1..200 do
      code = MemberCard.generate_code()
      assert String.length(code) == 10
      assert MemberCard.normalize_code(code) == code
    end
  end

  test "format_code puts a dash in the middle" do
    assert MemberCard.format_code("K7Q4M2XA9H") == "K7Q4M-2XA9H"
  end

  test "the QR link still fits a version 2 QR code, 38 characters (#969)" do
    url = MemberCard.qr_url(MemberCard.generate_code(), "https://verify.sarduty.com")
    assert url =~ ~r"^HTTPS://VERIFY.SARDUTY.COM/[A-Z0-9]{5}-[A-Z0-9]{5}$"
    assert String.length(url) == 38
  end

  test "normalize_code ignores case, spaces, and dashes" do
    assert MemberCard.normalize_code(" k7q4m-2xa9h ") == "K7Q4M2XA9H"
    assert MemberCard.normalize_code("K7Q4M 2XA9H") == "K7Q4M2XA9H"
  end

  test "normalize_code rejects what can't be a code" do
    assert MemberCard.normalize_code("K7Q4M2XA") == nil, "an 8-character code from before #969"
    assert MemberCard.normalize_code("K7Q4M2XA9H9") == nil
    assert MemberCard.normalize_code("K7Q4M2XA9HB") == nil
    assert MemberCard.normalize_code("K7Q4M2XA9H90") == nil
    assert MemberCard.normalize_code("https://evil.example/K7Q4M2XA9H") == nil
    assert MemberCard.normalize_code(nil) == nil
  end

  describe "status" do
    setup do
      team = team_fixture()
      %{team: team, member: member_fixture(team)}
    end

    test "is active for a current member, inactive once they leave, revoked when replaced",
         %{team: team, member: member} do
      left = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})

      assert MemberCard.status(%MemberCard{member: member}, @now) == :active
      assert MemberCard.status(%MemberCard{member: left}, @now) == :inactive
      assert MemberCard.status(%MemberCard{member: member, revoked_at: @now}, @now) == :revoked
    end

    # The same rule as logins (#514, #893): a retiring member is no longer a member.
    test "is inactive while the member is retiring, and active again once they aren't",
         %{team: team, member: member} do
      leavers = group_fixture(team)
      team |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id) |> Repo.update!()
      card = %MemberCard{member: member}

      membership = group_member_fixture(leavers, member)
      assert MemberCard.status(card, @now) == :inactive

      Repo.delete!(membership)
      assert MemberCard.status(card, @now) == :active
    end
  end

  describe "expires_at" do
    setup do
      team = %Team{d4h_refreshed_at: ~U[2026-09-30 13:05:00Z], timezone: "America/Vancouver"}
      %{card: %MemberCard{member: %Member{team: team}}}
    end

    test "rolls with the refresh while active", %{card: card} do
      card = %{card | expires_at: ~U[2026-11-01 06:59:59Z]}
      assert MemberCard.expires_at(card, :active) == ~U[2027-01-01 06:59:59Z]
    end

    test "stays put once the card isn't active", %{card: card} do
      card = %{card | expires_at: ~U[2026-11-01 06:59:59Z]}
      assert MemberCard.expires_at(card, :inactive) == ~U[2026-11-01 06:59:59Z]
      assert MemberCard.expires_at(card, :revoked) == ~U[2026-11-01 06:59:59Z]
    end

    test "starts from the refresh for a card never built while active", %{card: card} do
      assert MemberCard.expires_at(card, :inactive) == ~U[2027-01-01 06:59:59Z]
    end
  end

  describe "valid_until" do
    defp valid_until(refreshed_at),
      do:
        MemberCard.valid_until(%Team{
          d4h_refreshed_at: refreshed_at,
          timezone: "America/Toronto"
        })

    test "is the end of the month three months after the last check, in the team's zone" do
      # Checked in daylight time; Dec 31 ends in standard time.
      assert valid_until(~U[2026-09-30 19:00:00Z]) == ~U[2027-01-01 04:59:59Z]
      # Already Oct 1 in UTC, still Sep 30 in Toronto.
      assert valid_until(~U[2026-10-01 03:00:00Z]) == ~U[2027-01-01 04:59:59Z]
    end

    test "crosses the year from October" do
      assert valid_until(~U[2026-10-01 19:00:00Z]) == ~U[2027-02-01 04:59:59Z]
    end

    test "lands on the last day of a short month" do
      assert valid_until(~U[2026-11-30 19:00:00Z]) == ~U[2027-03-01 04:59:59Z]
      # Checked in standard time; Mar 31 ends in daylight time.
      assert valid_until(~U[2027-12-31 19:00:00Z]) == ~U[2028-04-01 03:59:59Z]
    end

    test "is nil before the team's first refresh" do
      assert valid_until(nil) == nil
    end
  end

  test "qr_url is the card's page on the verify site, in capitals" do
    assert MemberCard.qr_url("K7Q4M2XA9H", "https://verify.sarduty.com") ==
             "HTTPS://VERIFY.SARDUTY.COM/K7Q4M-2XA9H"
  end

  test "verify_url is the same page as a link people read" do
    assert MemberCard.verify_url("K7Q4M2XA9H", "https://verify.sarduty.com") ==
             "https://verify.sarduty.com/K7Q4M-2XA9H"
  end

  describe "code_from_scan" do
    @hosts ["verify.sarduty.com"]

    test "reads a bare code, as on the first cards" do
      assert MemberCard.code_from_scan("K7Q4M2XA9H", @hosts) == "K7Q4M2XA9H"
    end

    test "reads the code from a card's link, in any case" do
      for link <- [
            "HTTPS://VERIFY.SARDUTY.COM/K7Q4M-2XA9H",
            "https://verify.sarduty.com/k7q4m2xa9h",
            "https://verify.sarduty.com/K7Q4M-2XA9H/"
          ] do
        assert MemberCard.code_from_scan(link, @hosts) == "K7Q4M2XA9H"
      end
    end

    test "flags the app's own host: cards never linked there (#153)" do
      assert MemberCard.code_from_scan("https://sarduty.com/verify/K7Q4M-2XA9H", @hosts) ==
               {:other_site, "sarduty.com"}
    end

    test "flags a link to another site, the way a forged card would" do
      assert MemberCard.code_from_scan("https://sarduty-verify.com/K7Q4M-2XA9H", @hosts) ==
               {:other_site, "sarduty-verify.com"}

      assert MemberCard.code_from_scan(
               "https://verify.sarduty.com.evil.example/K7Q4M-2XA9H",
               @hosts
             ) ==
               {:other_site, "verify.sarduty.com.evil.example"}
    end

    test "is nil for a link to another page here, or text that isn't a code" do
      assert MemberCard.code_from_scan("https://verify.sarduty.com/orgs/nsr", @hosts) == nil
      assert MemberCard.code_from_scan("hello", @hosts) == nil
    end
  end
end
