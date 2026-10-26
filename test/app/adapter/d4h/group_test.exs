defmodule App.Adapter.D4H.GroupTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.Group

  test "a group owned by the organisation is marked, and the team's own is not (#546)" do
    owned =
      Group.build(%{
        "id" => 1763,
        "title" => "Aircraft",
        "owner" => %{"resourceType" => "Organisation", "id" => 40}
      })

    own = Group.build(%{"id" => 9, "title" => "Leavers", "owner" => %{"resourceType" => "Team"}})

    assert {owned.d4h_group_id, owned.title, owned.organization_owned} ==
             {1763, "Aircraft", true}

    refute own.organization_owned
    refute Group.build(%{"id" => 9, "title" => "Leavers"}).organization_owned
  end
end
