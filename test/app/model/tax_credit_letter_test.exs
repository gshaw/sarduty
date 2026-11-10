defmodule App.Model.TaxCreditLetterTest do
  use ExUnit.Case, async: true

  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter

  @timezone "America/Vancouver"
  @now ~U[2026-01-15 18:00:00Z]

  # A letter for `year` whose verify page shows `total`, against today's `now_total`.
  defp changes(year, total, now_total, now \\ @now) do
    shows = fn text ->
      [%{"label" => "Name", "text" => "Avery"}, %{"label" => "Total hours", "text" => text}]
    end

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

    test "last year's letters close on August 1, three months after members file" do
      assert changes(2025, "1 hour", "2 hours", ~U[2026-07-31 19:00:00Z]) != []
      assert changes(2025, "1 hour", "2 hours", ~U[2026-11-10 19:00:00Z]) == []
    end

    test "the year closes at midnight in the team's time zone" do
      # 11 p.m. on July 31, 2026 in Vancouver is already August 1 in UTC.
      assert changes(2025, "1 hour", "2 hours", ~U[2026-08-01 06:00:00Z]) != []
      assert changes(2025, "1 hour", "2 hours", ~U[2026-08-01 08:00:00Z]) == []
    end
  end

  describe "the letter year (#995)" do
    # Noon in Vancouver on each date.
    defp at(date), do: DateTime.new!(date, ~T[12:00:00], @timezone)

    defp list_year(date), do: date |> at() |> TaxCreditLetter.list_year(@timezone)
    defp settings_season?(date), do: date |> at() |> TaxCreditLetter.settings_season?(@timezone)

    test "the list opens on last year from January to April, and this year from May" do
      assert list_year(~D[2027-01-02]) == 2026
      assert list_year(~D[2027-04-30]) == 2026
      assert list_year(~D[2027-05-01]) == 2027
      assert list_year(~D[2026-11-10]) == 2026
    end

    test "it turns over in the team's time zone, not UTC" do
      # 9 p.m. on December 31, 2026 in Vancouver is already January 1, 2027 in UTC.
      evening = DateTime.new!(~D[2026-12-31], ~T[21:00:00], @timezone)
      assert TaxCreditLetter.list_year(evening, @timezone) == 2026
    end

    test "Needs attention names what letters need from team settings from December to April" do
      assert settings_season?(~D[2026-12-01])
      assert settings_season?(~D[2027-04-30])
      refute settings_season?(~D[2027-05-01])
      refute settings_season?(~D[2026-11-30])
    end
  end
end
