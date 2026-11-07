defmodule Web.Components.ColumnsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import Web.Components.Columns

  @zone "America/Toronto"

  defp text(rendered),
    do: rendered |> rendered_to_string() |> String.replace(~r/<[^>]+>/, " ") |> String.split()

  describe "the fits (/styles/table#fit)" do
    test "Date fits the 28th of every month, with the times under it when asked" do
      dates = date_fit(@zone)
      assert length(dates) == 12
      assert ["Sep", "28,", "2026"] in Enum.map(dates, &text/1)

      [jan | _] = date_fit(@zone, times: true)

      assert text(jan) == [
               "Jan",
               "28,",
               "2026",
               "20:08–23:59",
               "+1",
               ",",
               "ending",
               "1",
               "day",
               "later"
             ]
    end

    test "Expires fits an expired date and one with the most days left" do
      texts = @zone |> expires_fit() |> Enum.map(&text/1)
      assert ["Expired", "Sep", "28,", "2026"] in texts
      assert ["Sep", "28,", "2026", "60", "days"] in texts
    end

    test "Hours fits the longest of the minutes, each once" do
      assert hours_fit([45, 60, 8730, nil, 8730, 6360]) == ["106 hours", "145h 30m", "45 min"]
    end

    test "Last attended fits its longest words" do
      assert last_attended_fit() == ["Yesterday", "44 days ago", "18 months ago", "Never"]
    end
  end
end
