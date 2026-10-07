defmodule App.RepoTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Attendance
  alias App.Model.Member

  describe "paginate/2" do
    setup do
      team = team_fixture()

      members =
        for n <- 1..5 do
          member_fixture(team, %{name: "Member #{n}"})
        end

      query = from(m in Member, where: m.team_id == ^team.id, order_by: m.name)
      %{team: team, members: members, query: query}
    end

    test "first page", %{query: query, members: members} do
      page = Repo.paginate(query, page: 1, page_size: 2)

      assert Enum.map(page.entries, & &1.id) == ids(members, 0..1)
      assert page.page_number == 1
      assert page.page_size == 2
      assert page.total_entries == 5
      assert page.total_pages == 3
    end

    test "middle page", %{query: query, members: members} do
      page = Repo.paginate(query, page: 2, page_size: 2)

      assert Enum.map(page.entries, & &1.id) == ids(members, 2..3)
      assert page.page_number == 2
      assert page.total_entries == 5
      assert page.total_pages == 3
    end

    test "last page is short", %{query: query, members: members} do
      page = Repo.paginate(query, page: 3, page_size: 2)

      assert Enum.map(page.entries, & &1.id) == ids(members, 4..4)
      assert page.page_number == 3
      assert page.total_pages == 3
    end

    test "a page past the end has no entries", %{query: query} do
      page = Repo.paginate(query, page: 9, page_size: 2)

      assert page.entries == []
      assert page.page_number == 9
      assert page.total_entries == 5
      assert page.total_pages == 3
    end

    test "a page below 1 is page 1", %{query: query, members: members} do
      page = Repo.paginate(query, page: 0, page_size: 2)

      assert Enum.map(page.entries, & &1.id) == ids(members, 0..1)
      assert page.page_number == 1
    end

    test "defaults to page 1 of 50", %{query: query} do
      page = Repo.paginate(query, page: nil, page_size: nil)

      assert length(page.entries) == 5
      assert page.page_number == 1
      assert page.page_size == 50
      assert page.total_pages == 1
    end

    test "caps the page size at 1000", %{query: query} do
      assert Repo.paginate(query, page_size: 5000).page_size == 1000
    end

    test "an empty result has one page", %{query: query} do
      page = query |> where([m], m.name == "Nobody") |> Repo.paginate()

      assert page.entries == []
      assert page.total_entries == 0
      assert page.total_pages == 1
    end

    test "counts a joined summary with a custom select once per row", %{team: team} do
      [first, second | _] = Member |> where(team_id: ^team.id) |> order_by(:name) |> Repo.all()
      activity = activity_fixture(team)
      other_activity = activity_fixture(team)
      attendance_fixture(activity, first, %{duration_in_minutes: 30})
      attendance_fixture(other_activity, first, %{duration_in_minutes: 45})
      attendance_fixture(activity, second, %{duration_in_minutes: 60})

      # The shape of MemberFilterViewModel.build_paginated_content/2.
      summary =
        from(a in Attendance,
          group_by: a.member_id,
          select: %{member_id: a.member_id, total_minutes: sum(a.duration_in_minutes)}
        )

      query =
        from(m in Member,
          left_join: s in subquery(summary),
          on: m.id == s.member_id,
          where: m.team_id == ^team.id,
          order_by: [desc: fragment("total_minutes"), asc: m.name],
          select: %{
            member: m,
            total_minutes: fragment("? as total_minutes", coalesce(s.total_minutes, 0))
          }
        )

      page = Repo.paginate(query, page: 1, page_size: 2)

      assert page.total_entries == 5
      assert page.total_pages == 3
      assert [%{member: %Member{}, total_minutes: 75}, %{total_minutes: 60}] = page.entries
    end
  end

  defp ids(members, range), do: members |> Enum.slice(range) |> Enum.map(& &1.id)
end
