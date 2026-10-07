defmodule App.ViewModel.TaxCreditLetterFilterViewModelTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Activity
  alias App.ViewModel.TaxCreditLetterFilterViewModel

  setup do
    team = team_fixture(%{timezone: "America/Vancouver"})
    member = member_fixture(team, %{name: "Avery"})
    %{team: team, member: member}
  end

  defp attend(team, member, started_at, minutes, attrs \\ %{}) do
    {activity_attrs, attrs} = Map.pop(attrs, :activity, %{})
    activity = activity_fixture(team, Map.merge(%{started_at: started_at}, activity_attrs))
    finished_at = DateTime.add(started_at, minutes * 60)

    attendance_fixture(
      activity,
      member,
      Map.merge(
        %{started_at: started_at, finished_at: finished_at, duration_in_minutes: minutes},
        attrs
      )
    )
  end

  defp find_all(team, year, filter \\ "any", sort \\ "total") do
    TaxCreditLetterFilterViewModel.find_all(team, %TaxCreditLetterFilterViewModel{
      year: year,
      filter: filter,
      sort: sort
    })
  end

  test "lists the same hours the letter counts, overlaps merged", %{team: team, member: member} do
    attend(team, member, ~U[2025-03-01 17:00:00Z], 180)
    attend(team, member, ~U[2025-03-01 19:00:00Z], 120)

    assert [%{member: %{id: id}, primary_minutes: 240, total_minutes: 240}] = find_all(team, 2025)
    assert id == member.id
  end

  test "leaves out rows not attended, on deleted activities, or on another team",
       %{team: team, member: member} do
    attend(team, member, ~U[2025-03-01 17:00:00Z], 60)
    attend(team, member, ~U[2025-03-02 17:00:00Z], 60, %{status: "absent"})

    attend(team, member, ~U[2025-03-03 17:00:00Z], 60, %{
      activity: %{deleted_at: ~U[2025-04-01 00:00:00Z]}
    })

    other_team = team_fixture()
    attend(other_team, member_fixture(other_team), ~U[2025-03-04 17:00:00Z], 60)

    assert [%{primary_minutes: 60}] = find_all(team, 2025)
  end

  test "midnight on January 1 starts the year, with or without a stored Z",
       %{team: team, member: member} do
    attend(team, member, ~U[2026-01-01 08:00:00Z], 60)

    attendance =
      attend(team, member, ~U[2026-01-01 08:00:00Z], 60, %{
        activity: %{tags: [Activity.secondary_hours_tag()]}
      })

    # Older rows were written without the Z.
    Repo.query!("UPDATE attendances SET started_at = '2026-01-01T08:00:00' WHERE id = ?", [
      attendance.id
    ])

    assert find_all(team, 2025) == []
    assert [%{primary_minutes: 60, secondary_minutes: 0}] = find_all(team, 2026)
  end

  test "filters by total hours and sorts by them", %{team: team, member: member} do
    other = member_fixture(team, %{name: "Blake"})
    attend(team, member, ~U[2025-03-01 17:00:00Z], 60)
    attend(team, other, ~U[2025-03-02 17:00:00Z], 120 * 60)
    _none = member_fixture(team, %{name: "Casey"})

    assert team |> find_all(2025, "any") |> Enum.map(& &1.member.name) == ["Blake", "Avery"]
    assert team |> find_all(2025, "100") |> Enum.map(& &1.member.name) == ["Blake"]

    assert team
           |> find_all(2025, "none", "name")
           |> Enum.map(& &1.member.name)
           |> Enum.member?("Casey")
  end

  test "shows the member's letter for the year", %{team: team, member: member} do
    attend(team, member, ~U[2025-03-01 17:00:00Z], 60)
    letter = tax_credit_letter_fixture(member, %{year: 2025})
    _older = tax_credit_letter_fixture(member, %{year: 2024})

    assert [%{tax_credit_letter_id: id, tax_credit_letter_ref_id: ref_id}] = find_all(team, 2025)
    assert {id, ref_id} == {letter.id, letter.ref_id}
  end
end
