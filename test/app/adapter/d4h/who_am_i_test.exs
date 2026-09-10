defmodule App.Adapter.D4H.WhoAmITest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.WhoAmI

  defp member(member_id, owner) do
    %{"resourceType" => "Member", "id" => member_id, "name" => "Sam", "owner" => owner}
  end

  test "lists every team the member belongs to" do
    whoami =
      WhoAmI.build(%{
        "members" => [
          member(1, %{"resourceType" => "Team", "id" => 10, "title" => "North"}),
          member(2, nil),
          member(3, %{"resourceType" => "Team", "id" => 20, "title" => "South"})
        ]
      })

    assert whoami.d4h_team_id == 10
    assert whoami.d4h_team_ids == [10, 20]
  end

  test "is nil without members" do
    assert WhoAmI.build(%{"members" => []}) == nil
  end
end
