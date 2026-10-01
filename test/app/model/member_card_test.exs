defmodule App.Model.MemberCardTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team

  @now ~U[2026-09-30 12:00:00Z]

  test "generate_code makes 8 characters that normalize to themselves" do
    for _ <- 1..200 do
      code = MemberCard.generate_code()
      assert String.length(code) == 8
      assert MemberCard.normalize_code(code) == code
    end
  end

  test "format_code puts a dash in the middle" do
    assert MemberCard.format_code("K7Q4M2XA") == "K7Q4-M2XA"
  end

  test "normalize_code ignores case, spaces, and dashes" do
    assert MemberCard.normalize_code(" k7q4-m2xa ") == "K7Q4M2XA"
    assert MemberCard.normalize_code("K7Q4 M2XA") == "K7Q4M2XA"
    assert MemberCard.normalize_code("AAAAAAAA") == "AAAAAAAA"
  end

  test "normalize_code rejects what can't be a code" do
    assert MemberCard.normalize_code("K7Q4M2X") == nil
    assert MemberCard.normalize_code("K7Q4M2XAB") == nil
    assert MemberCard.normalize_code("K7Q4M2X0") == nil
    assert MemberCard.normalize_code("https://evil.example/K7Q4M2XA") == nil
    assert MemberCard.normalize_code(nil) == nil
  end

  test "status is active for a current member, inactive once they leave, revoked when cancelled" do
    current = %Member{left_at: nil}
    left = %Member{left_at: ~U[2026-01-01 00:00:00Z]}

    assert MemberCard.status(%MemberCard{member: current}, @now) == :active
    assert MemberCard.status(%MemberCard{member: left}, @now) == :inactive
    assert MemberCard.status(%MemberCard{member: current, revoked_at: @now}, @now) == :revoked
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

  test "qr_url is the card's /verify page in capitals" do
    assert MemberCard.qr_url("K7Q4M2XA", "https://sarduty.com") ==
             "HTTPS://SARDUTY.COM/VERIFY/K7Q4-M2XA"
  end

  describe "code_from_scan" do
    test "reads a bare code, as on older cards" do
      assert MemberCard.code_from_scan("K7Q4M2XA", "sarduty.com") == "K7Q4M2XA"
    end

    test "reads the code from a link to this site, in any case" do
      for link <- [
            "HTTPS://SARDUTY.COM/VERIFY/K7Q4-M2XA",
            "https://sarduty.com/verify/k7q4m2xa",
            "https://sarduty.com/verify/K7Q4-M2XA/"
          ] do
        assert MemberCard.code_from_scan(link, "sarduty.com") == "K7Q4M2XA"
      end
    end

    test "flags a link to another site, the way a forged card would" do
      assert MemberCard.code_from_scan(
               "https://sarduty-verify.com/verify/K7Q4-M2XA",
               "sarduty.com"
             ) ==
               {:other_site, "sarduty-verify.com"}

      assert MemberCard.code_from_scan(
               "https://sarduty.com.evil.example/verify/K7Q4-M2XA",
               "sarduty.com"
             ) ==
               {:other_site, "sarduty.com.evil.example"}
    end

    test "is nil for a link to another page here, or text that isn't a code" do
      assert MemberCard.code_from_scan("https://sarduty.com/login", "sarduty.com") == nil
      assert MemberCard.code_from_scan("hello", "sarduty.com") == nil
    end
  end
end
