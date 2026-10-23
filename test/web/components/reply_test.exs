defmodule Web.Components.ReplyTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.Attendance
  alias Web.Components.Reply

  defp text({yes, no, none}, started?),
    do: Reply.counts_text(%{attending: yes, absent: no, requested: none}, started?)

  test "the counts use the reply words before the start, and D4H's from it" do
    assert text({6, 2, 5}, false) ==
             "6 signed up · 2 can't make it · 5 no reply"

    assert text({6, 2, 5}, true) == "6 attended · 2 absent · 5 no reply"
  end

  test "a zero is left out, except the first" do
    assert text({0, 0, 13}, false) == "0 signed up · 13 no reply"
    assert text({4, 0, 2}, false) == "4 signed up · 2 no reply"
    assert text({0, 0, 0}, true) == "0 attended"
  end

  test "the counts are numbers as people read them" do
    assert text({1204, 1, 0}, false) == "1,204 signed up · 1 can't make it"
  end

  test "replies are open to an invited member until the start" do
    now = ~U[2026-10-26 16:00:00Z]
    coming = %Activity{started_at: ~U[2026-10-29 02:00:00Z]}
    row = %Attendance{status: "requested"}

    assert Reply.open?(row, coming, now)
    refute Reply.open?(nil, coming, now)
    refute Reply.open?(row, %{coming | started_at: now}, now)
    refute Reply.open?(row, %{coming | deleted_at: ~U[2026-10-25 00:00:00Z]}, now)
  end
end
