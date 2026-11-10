defmodule App.Model.TaxCreditLetterTest do
  use ExUnit.Case, async: true

  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter

  @timezone "America/Vancouver"
  @now ~U[2026-01-15 18:00:00Z]

  # A letter for `year` whose verify page shows `total`, against today's `now_total`.
  defp changes(year, total, now_total, now \\ @now) do
    shows = fn text -> [%{"label" => "Name", "text" => "Avery"}, %{"label" => "Total hours", "text" => text}] end
    letter = %PublishedPDF{year: year, shows: shows.(total)}
    TaxCreditLetter.changes(letter, %{shows: shows.(now_total), keep: %{}}, now, @timezone)
  end

  describe "changes/4 (#995)" do
    test "the same verify page is up to date, in any year" do
      assert changes(2025, "1 hour", "1 hour") == []
      assert changes(2020, "1 hour", "1 hour") == []
    end

    test "last year's letter and this year's go out of date" do
      assert changes(2025, "1 hour", "1h 30m") == ["Total hours: 1 hour → 1h 30m"]
      assert changes(2026, "1 hour", "1h 30m") == ["Total hours: 1 hour → 1h 30m"]
    end

    test "a closed year's letter never does: a member may have filed it" do
      assert changes(2024, "1 hour", "1h 30m") == []
    end

    test "the year closes at midnight in the team's time zone" do
      # The evening of December 31, 2026 in Vancouver: 2025 letters are still open.
      assert changes(2025, "1 hour", "2 hours", ~U[2027-01-01 05:00:00Z]) != []
      assert changes(2025, "1 hour", "2 hours", ~U[2027-01-01 09:00:00Z]) == []
    end
  end
end
