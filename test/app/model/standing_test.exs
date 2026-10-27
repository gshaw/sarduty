defmodule App.Model.StandingTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.Standing
  alias App.Repo

  @today ~D[2026-10-18]
  @now ~U[2026-10-18 18:00:00Z]

  defp period(starts_on, ends_on), do: %MemberAwayPeriod{starts_on: starts_on, ends_on: ends_on}

  defp person, do: %{not_a_person: false}

  test "a member with no current away period is active" do
    past = period(~D[2026-01-01], ~D[2026-03-01])
    upcoming = period(~D[2026-11-01], ~D[2026-12-01])

    assert Standing.of(person(), [past, upcoming], false, @today, @now) == :active
  end

  test "the first and last days are both away" do
    for p <- [period(@today, ~D[2026-11-01]), period(~D[2026-10-01], @today)],
        do: assert({:away, ^p} = Standing.of(person(), [p], false, @today, @now))
  end

  test "of overlapping away periods, the one that ends last decides" do
    short = period(~D[2026-10-01], ~D[2026-10-31])
    long = period(~D[2026-09-01], ~D[2027-03-01])

    assert {:away, ^long} = Standing.of(person(), [short, long], false, @today, @now)
  end

  test "retiring wins over an away period; not a person wins over retiring (#514)" do
    p = period(~D[2026-10-01], ~D[2026-10-31])
    assert Standing.of(person(), [p], true, @today, @now) == :retiring
    assert Standing.of(%{not_a_person: true}, [p], true, @today, @now) == :not_a_person
  end

  test "retired wins over the rest, from D4H" do
    p = period(~D[2026-10-01], ~D[2026-10-31])
    left = %{not_a_person: true, left_at: ~U[2026-10-10 18:00:00Z]}
    leaving = %{not_a_person: false, left_at: ~U[2026-11-01 18:00:00Z]}
    retired = %{not_a_person: false, d4h_status: "RETIRED"}

    assert Standing.of(left, [p], true, @today, @now) == :retired
    assert {:away, ^p} = Standing.of(leaving, [p], false, @today, @now)
    assert Standing.of(retired, [], true, @today, @now) == :retired
  end

  test "a member sees Away as Active, and every other standing as it is (#440)" do
    away = {:away, period(~D[2026-10-01], ~D[2026-10-31])}

    assert Standing.visible(away, false) == :active
    assert Standing.visible(away, true) == away

    for standing <- [:retiring, :not_a_person, :retired],
        do: assert(Standing.visible(standing, false) == standing)
  end

  test "each standing reads as text" do
    assert Standing.text(:active) == "Active"
    assert Standing.text(:retiring) == "Retiring"
    assert Standing.text(:not_a_person) == "Not a person"
    assert Standing.text(:retired) == "Retired"
    assert Standing.order() == [:retired, :not_a_person, :retiring, :away, :active]
  end

  # Standing.dynamic/1 is Standing.of/5 in SQL. Every mix of the parts that decide a
  # standing, through both, must agree, so the order can't drift between the two.
  test "the query and the pure function agree on every mix of standings" do
    team = team_fixture(%{timezone: "America/Vancouver"})
    retiring_group = group_fixture(team)
    other_group = group_fixture(team)

    team =
      team
      |> Ecto.Changeset.change(retiring_d4h_group_id: retiring_group.d4h_group_id)
      |> Repo.update!()

    members =
      for retired? <- [false, true],
          not_a_person <- [false, true],
          retiring? <- [false, true],
          away? <- [false, true] do
        member =
          member_fixture(team, %{
            not_a_person: not_a_person,
            left_at: if(retired?, do: ~U[2026-10-01 18:00:00Z])
          })

        if retiring?, do: group_member_fixture(retiring_group, member)
        group_member_fixture(other_group, member)
        if away?, do: away_period_fixture(member, ~D[2026-10-01], ~D[2026-10-31])
        member
      end

    standing = Standing.dynamic(@now)

    from_sql =
      Member
      |> where([m], m.team_id == ^team.id)
      |> Standing.join(team, @today)
      |> select(^%{id: dynamic([m], m.id), standing: standing})
      |> Repo.all()
      |> Map.new(&{&1.id, &1.standing})

    retiring = Standing.retiring_ids(team)

    for member <- members do
      expected =
        member
        |> Standing.of(
          MemberAwayPeriod.for_member(member),
          MapSet.member?(retiring, member.id),
          @today,
          @now
        )
        |> Standing.kind()
        |> Atom.to_string()

      assert from_sql[member.id] == expected
    end

    assert from_sql |> Map.values() |> Enum.uniq() |> Enum.sort() ==
             ~w(active away not_a_person retired retiring)
  end

  test "no Retiring group, or one that was deleted, makes nobody retiring" do
    team = team_fixture()
    group = group_fixture(team)
    member = member_fixture(team)
    group_member_fixture(group, member)

    assert Standing.retiring_ids(team) == MapSet.new()

    gone = %{team | retiring_d4h_group_id: 424_242}
    assert Standing.retiring_ids(gone) == MapSet.new()

    set = %{team | retiring_d4h_group_id: group.d4h_group_id}
    assert Standing.retiring_ids(set) == MapSet.new([member.id])
  end
end
