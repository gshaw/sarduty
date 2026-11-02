defmodule App.ViewModel.AttendanceFilterViewModelTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.ViewModel.AttendanceFilterViewModel

  # 60 rows over two pages of 50: three activities of 20 rows each (D4H can keep several
  # for one member), sharing its start, and durations of 60, 120, or 180 minutes, so every
  # sort has ties that cross a page.
  setup do
    team = team_fixture()
    member = team |> member_fixture() |> Repo.preload(:team)
    start = DateTime.utc_now() |> DateTime.add(-30, :day) |> DateTime.truncate(:second)

    rows =
      for day <- 0..2,
          activity = activity_fixture(team, %{started_at: DateTime.add(start, day, :day)}),
          n <- 1..20 do
        attendance_fixture(activity, member, %{duration_in_minutes: 60 * rem(n, 3) + 60})
      end

    %{member: member, rows: rows}
  end

  defp all_pages(member, sort) do
    Enum.flat_map([1, 2], fn page ->
      {:ok, options, _} =
        AttendanceFilterViewModel.validate(%{"when" => "all", "sort" => sort, "page" => page})

      page = AttendanceFilterViewModel.build_paginated_content(member, options)
      Enum.map(page.entries, & &1.id)
    end)
  end

  test "every sort lists each row once across pages, ties in id order", %{
    member: member,
    rows: rows
  } do
    for {sort, key} <- [
          {"date", &DateTime.to_unix(&1.started_at)},
          {"hours", & &1.duration_in_minutes},
          {"id", & &1.activity_id}
        ] do
      ascending = rows |> Enum.sort_by(&{key.(&1), &1.id}) |> Enum.map(& &1.id)

      assert all_pages(member, sort) == ascending
      assert all_pages(member, sort <> "-") == Enum.reverse(ascending)
    end
  end
end
