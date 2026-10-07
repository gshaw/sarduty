defmodule Web.VerifyLimitTest do
  use App.DataCase

  alias App.Model.Event
  alias Web.VerifyLimit

  test "records the miss that reaches the limit, once" do
    ip = "test-#{System.unique_integer([:positive])}"
    for _ <- 1..25, do: VerifyLimit.miss(ip)

    assert VerifyLimit.limited?(ip)
    assert %Event{ip: ^ip} = Event.get_last(:verify_limit_reached)

    assert Event.count_since(:verify_limit_reached, DateTime.add(DateTime.utc_now(), -1, :minute)) ==
             1
  end
end
