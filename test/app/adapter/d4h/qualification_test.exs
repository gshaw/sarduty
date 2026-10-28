defmodule App.Adapter.D4H.QualificationTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.Qualification

  test "a qualification owned by the organisation is marked, and the team's own is not (#652)" do
    owned =
      Qualification.build(%{
        "id" => 312,
        "title" => "GSAR Team Member",
        "owner" => %{"resourceType" => "Organisation", "id" => 7}
      })

    own =
      Qualification.build(%{
        "id" => 8,
        "title" => "Driver Truck",
        "owner" => %{"resourceType" => "Team"}
      })

    assert {owned.d4h_qualification_id, owned.title, owned.organization_owned} ==
             {312, "GSAR Team Member", true}

    refute own.organization_owned
    refute Qualification.build(%{"id" => 8, "title" => "Driver Truck"}).organization_owned
  end
end
