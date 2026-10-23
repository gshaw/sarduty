defmodule App.ViewModel.MilestoneFilterViewModelTest do
  use ExUnit.Case, async: true

  alias App.ViewModel.MilestoneFilterViewModel

  @tz "America/Vancouver"
  # Oct 23, 2026, 10:00 in Vancouver.
  @now ~U[2026-10-23 17:00:00Z]

  defp milestone(member_id, kind, on),
    do: %{member: %{id: member_id, name: "Member #{member_id}"}, kind: kind, count: 1, on: on}

  defp options(params) do
    {:ok, options, _changeset} = MilestoneFilterViewModel.validate(params)
    options
  end

  defp milestones do
    [
      milestone(1, :hours, ~D[2026-10-23]),
      milestone(2, :years, ~D[2026-07-26]),
      milestone(1, :incidents, ~D[2026-07-24]),
      milestone(2, :hours, ~D[2025-12-31])
    ]
  end

  defp ons(milestones), do: Enum.map(milestones, & &1.on)

  test "opens on the last 90 days, today included" do
    assert milestones() |> MilestoneFilterViewModel.filter(options(%{}), @tz, @now) |> ons() ==
             [~D[2026-10-23], ~D[2026-07-26]]
  end

  test "filters by member, kind, a year, and All" do
    assert milestones()
           |> MilestoneFilterViewModel.filter(
             options(%{"member" => "2", "when" => "all"}),
             @tz,
             @now
           )
           |> ons() ==
             [~D[2026-07-26], ~D[2025-12-31]]

    assert milestones()
           |> MilestoneFilterViewModel.filter(
             options(%{"kind" => "hours", "when" => "all"}),
             @tz,
             @now
           )
           |> ons() ==
             [~D[2026-10-23], ~D[2025-12-31]]

    assert milestones()
           |> MilestoneFilterViewModel.filter(options(%{"when" => "2025"}), @tz, @now)
           |> ons() ==
             [~D[2025-12-31]]
  end

  test "refuses a kind or period it doesn't know" do
    assert {:error, _} = MilestoneFilterViewModel.validate(%{"kind" => "badges"})
    assert {:error, _} = MilestoneFilterViewModel.validate(%{"when" => "forever"})
  end

  test "pages by 50" do
    many = for day <- 1..60, do: milestone(1, :hours, Date.add(~D[2026-01-01], day))
    page = MilestoneFilterViewModel.page(many, 2)
    assert {page.total_entries, page.total_pages, length(page.entries)} == {60, 2, 10}
  end

  test "offers the members with a milestone by name, and each year with one" do
    assert MilestoneFilterViewModel.member_kinds(milestones()) == [
             {"Member 1", "1"},
             {"Member 2", "2"}
           ]

    assert {"2025", "2025"} in MilestoneFilterViewModel.when_kinds(milestones())
  end
end
