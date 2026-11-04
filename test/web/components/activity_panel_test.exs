defmodule Web.Components.ActivityPanelTest do
  use ExUnit.Case, async: true

  alias Web.Components.ActivityPanel

  @tz "America/Toronto"
  # Tue Nov 3, 2026, 12:00 in Toronto.
  @now ~U[2026-11-03 17:00:00Z]

  defp text(start_hours, hours, published? \\ false) do
    started_at = DateTime.add(@now, round(start_hours * 3600))

    activity = %{
      started_at: started_at,
      finished_at: DateTime.add(started_at, hours * 3600),
      is_published: published?
    }

    ActivityPanel.state_text(activity, @now, @tz)
  end

  test "coming: hours within a day, then tomorrow, then days" do
    assert text(3, 2) == "Starts in 3 hours"
    assert text(28, 2) == "Starts tomorrow"
    assert text(4 * 24, 2) == "Starts in 4 days"
  end

  test "under way: the finish time, with its day when it's not today" do
    assert text(-1, 4) == "Under way · finishes 15:00"
    assert text(-1, 30) == "Under way · finishes Tomorrow, 17:00"
  end

  test "finished: how long ago, and whether it's published" do
    assert text(-5, 1) == "Finished 4 hours ago · not published"
    assert text(-3 * 24, 5) == "Finished 3 days ago · not published"
    assert text(-3 * 24, 5, true) == "Finished 3 days ago · published"
  end
end
