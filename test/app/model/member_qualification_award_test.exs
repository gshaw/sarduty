defmodule App.Model.MemberQualificationAwardTest do
  use ExUnit.Case, async: true

  alias App.Model.MemberQualificationAward

  @now ~U[2026-10-23 12:00:00Z]

  defp award(member_id, starts_days, ends_days) do
    %{
      member_id: member_id,
      starts_at: starts_days && DateTime.add(@now, starts_days, :day),
      ends_at: ends_days && DateTime.add(@now, ends_days, :day)
    }
  end

  describe "split_by_member/2" do
    test "a member who renewed is active once, not also expired" do
      current = award(1, -30, nil)

      {active, expired} =
        MemberQualificationAward.split_by_member([current, award(1, -800, -30)], @now)

      assert active == [current]
      assert expired == []
    end

    test "a member whose awards all ended is expired once, with the newest" do
      newest = award(2, -500, -10)

      {active, expired} =
        MemberQualificationAward.split_by_member([newest, award(2, -900, -500)], @now)

      assert active == []
      assert expired == [newest]
    end

    test "a member whose only award hasn't started is in neither" do
      assert {[], []} = MemberQualificationAward.split_by_member([award(3, 5, 400)], @now)
    end

    test "keeps the order given" do
      a = award(1, -10, nil)
      b = award(2, -20, nil)

      assert {[^b, ^a], []} = MemberQualificationAward.split_by_member([b, a], @now)
    end
  end

  # D4H keeps an award's end as a day. The copy keeps its start on the team's clock, and
  # the award is good through that day (#1058).
  describe "an award expiring Nov 12 on a Pacific team" do
    setup do
      ends_at = Service.Convert.day_start(~D[2026-11-12], "America/Vancouver")
      %{award: %{starts_at: ~U[2021-11-12 08:00:00Z], ends_at: ends_at}, ends_at: ends_at}
    end

    test "is good through the evening of Nov 12, and expired from midnight", ctx do
      evening = DateTime.add(ctx.ends_at, 86_399)
      midnight = DateTime.add(ctx.ends_at, 1, :day)

      assert MemberQualificationAward.active?(ctx.award, evening)
      refute MemberQualificationAward.expired?(ctx.award, evening)
      refute MemberQualificationAward.active?(ctx.award, midnight)
      assert MemberQualificationAward.expired?(ctx.award, midnight)
    end

    test "is good on the evening of Nov 11, when it is already Nov 12 in UTC", ctx do
      evening = DateTime.add(ctx.ends_at, -3600)
      assert DateTime.to_date(evening) == ~D[2026-11-12]
      assert MemberQualificationAward.active?(ctx.award, evening)
    end
  end
end
