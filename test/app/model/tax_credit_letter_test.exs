defmodule App.Model.TaxCreditLetterTest do
  use ExUnit.Case, async: true

  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter

  @timezone "America/Vancouver"
  @now ~U[2026-01-15 18:00:00Z]

  describe "hours_status/4" do
    # A letter for `year` that says {primary, secondary}, against today's count.
    defp status({year, primary, secondary}, {now_primary, now_secondary}, now \\ @now) do
      letter = %PublishedPDF{
        year: year,
        keep: %{"hours.primary" => primary, "hours.secondary" => secondary}
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
