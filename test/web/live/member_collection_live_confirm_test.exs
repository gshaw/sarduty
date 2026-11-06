defmodule Web.MemberCollectionLiveConfirmTest do
  # Remove from group's confirm at 2, 6, and 12 ticked (/styles/confirm-dialog#many).
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias Web.MemberCollectionLive

  @groups [{"Trainees", 7}]

  defp confirm(n, group_id \\ 7) do
    rows = for id <- 1..14, do: %{member: %Member{id: id, name: "Member #{id}"}}
    selected = MapSet.new(1..n//1)
    MemberCollectionLive.remove_confirm(selected, rows, group_id, @groups)
  end

  test "names up to 3" do
    assert confirm(2) == %{"data-confirm" => "Remove Member 1 and Member 2 from Trainees?"}
  end

  test "counts from 4" do
    assert confirm(6) == %{"data-confirm" => "Remove 6 members from Trainees?"}
  end

  test "waits on a box naming the count from 10" do
    assert confirm(12) == %{
             "data-confirm" => "Remove 12 members from Trainees?",
             "data-confirm-check" => "I understand 12 members leave Trainees."
           }
  end

  test "asks nothing without a group or ticks" do
    assert confirm(0) == %{}
    assert confirm(1, nil) == %{}
  end
end
