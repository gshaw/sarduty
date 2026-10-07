defmodule App.Model.TaxCreditLetterTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.TaxCreditLetter

  @timezone "America/Vancouver"
  @now ~U[2026-01-15 18:00:00Z]

  describe "reference numbers" do
    # cspell:ignore ABCDEFGHJKMNPQRSTVWXYZ SRVTCK -- the code alphabet, and a typed number
    test "a new one is SRVTC and 8 characters from the ID card alphabet" do
      ref_id = TaxCreditLetter.generate_ref_id()
      assert ref_id =~ ~r/^SRVTC-[23456789ABCDEFGHJKMNPQRSTVWXYZ]{8}$/
      assert TaxCreditLetter.parse_ref_id(ref_id) == {:current, ref_id}
    end

    test "case, spaces, dashes, and the prefix do not matter" do
      for typed <- ["srvtc-k7q4m2xa", "K7Q4-M2XA", " SRVTC K7Q4 M2XA ", "SRVTCK7Q4M2XA"] do
        assert TaxCreditLetter.parse_ref_id(typed) == {:current, "SRVTC-K7Q4M2XA"}, typed
      end
    end

    test "a reference number from before #207 is old" do
      assert TaxCreditLetter.parse_ref_id("SRVTC-M4K11") == {:old, "SRVTC-M4K11"}
      assert TaxCreditLetter.parse_ref_id("m4k11") == {:old, "SRVTC-M4K11"}
    end

    test "anything else is nil" do
      for typed <- ["", "SRVTC-", "K7Q4M2X", "K7Q4M2XAB", "SRVTC-K7Q4M2X0", "../etc", nil] do
        assert TaxCreditLetter.parse_ref_id(typed) == nil, inspect(typed)
      end
    end

    test "only a current reference number can verify alone" do
      assert TaxCreditLetter.current_ref_id?(%TaxCreditLetter{ref_id: "SRVTC-K7Q4M2XA"})
      refute TaxCreditLetter.current_ref_id?(%TaxCreditLetter{ref_id: "SRVTC-M4K11"})
    end

    test "the verify link is the letter's page on the verify site" do
      letter = %TaxCreditLetter{ref_id: "SRVTC-K7Q4M2XA"}

      assert TaxCreditLetter.verify_url(letter, "https://verify.sarduty.com") ==
               "https://verify.sarduty.com/letters/SRVTC-K7Q4M2XA"
    end
  end

  describe "last_name_matches?/2" do
    test "reads both ways D4H writes names, ignoring case" do
      assert TaxCreditLetter.last_name_matches?(%Member{name: "Nadia Mercer"}, "mercer")
      assert TaxCreditLetter.last_name_matches?(%Member{name: "Mercer, Nadia"}, " Mercer ")
      assert TaxCreditLetter.last_name_matches?(%Member{name: "Ana de la Cruz"}, "de la Cruz")
    end

    test "a first name, part of a name, or nothing does not match" do
      refute TaxCreditLetter.last_name_matches?(%Member{name: "Nadia Mercer"}, "Nadia")
      refute TaxCreditLetter.last_name_matches?(%Member{name: "Mercer, Nadia"}, "Nadia")
      refute TaxCreditLetter.last_name_matches?(%Member{name: "Nadia Mercer"}, "cer")
      refute TaxCreditLetter.last_name_matches?(%Member{name: "Nadia Mercer"}, "")
    end
  end

  describe "parse_minutes/1" do
    defp parse(primary, secondary) do
      TaxCreditLetter.parse_minutes("""
      Name: Sam Doe

      Primary Hours: #{primary}
      Secondary Hours: #{secondary}
      Total Hours: whatever
      """)
    end

    test "reads the hours as the letter writes them" do
      assert parse("143 hours, 30 minutes", "72 hours") == {143 * 60 + 30, 72 * 60}
      assert parse("1 hour, 1 minute", "45 minutes") == {61, 45}
      assert parse("0 hours", "1 hour") == {0, 60}
    end

    test "a bare number has no unit, so the letter stays empty" do
      # Some early letters say "Primary Hours: 708": hours or minutes, nobody can tell.
      assert parse("708", "77") == nil
    end

    test "a letter missing either line stays empty" do
      assert TaxCreditLetter.parse_minutes("Primary Hours: 3 hours\n") == nil
      assert TaxCreditLetter.parse_minutes("Test letter content") == nil
      assert TaxCreditLetter.parse_minutes(nil) == nil
    end
  end

  describe "hours_status/4" do
    # A letter for `year` that says {primary, secondary}, against today's count.
    defp status({year, primary, secondary}, {now_primary, now_secondary}, now \\ @now) do
      letter = %TaxCreditLetter{
        year: year,
        primary_minutes: primary,
        secondary_minutes: secondary
      }

      hours = %{
        primary_minutes: now_primary,
        secondary_minutes: now_secondary,
        total_minutes: now_primary + now_secondary
      }

      TaxCreditLetter.hours_status(letter, hours, now, @timezone)
    end

    test "the same hours are the same, in any year" do
      assert status({2025, 60, 30}, {60, 30}) == :same
      assert status({2020, 60, 30}, {60, 30}) == :same
    end

    test "different hours on the year whose letters go out now are a change" do
      assert status({2025, 60, 30}, {90, 30}) == :changed
      # Moving minutes between kinds is a change too, even with the same total.
      assert status({2025, 60, 30}, {30, 60}) == :changed
    end

    test "a letter for the year still under way warns too" do
      assert status({2026, 60, 0}, {90, 0}) == :changed
    end

    test "different hours on an older letter are noted, not a warning" do
      assert status({2024, 60, 30}, {90, 30}) == :changed_old
    end

    test "the current year turns over at midnight in the team's time zone" do
      # The evening of December 31, 2026 in Vancouver: 2025 letters are still current.
      assert status({2025, 60, 0}, {90, 0}, ~U[2027-01-01 05:00:00Z]) == :changed
      assert status({2025, 60, 0}, {90, 0}, ~U[2027-01-01 09:00:00Z]) == :changed_old
    end

    test "an old letter with no saved hours has nothing to compare" do
      assert status({2025, nil, nil}, {90, 0}) == :unknown
    end
  end
end
