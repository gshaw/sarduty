defmodule App.Adapter.D4H.TagTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.Tag

  test "a tag keeps its owner, team or organisation" do
    tag =
      Tag.build(%{
        "id" => 12,
        "title" => "SRVTC Hours",
        "resourceType" => "Tag",
        "owner" => %{"resourceType" => "Organisation", "id" => 40}
      })

    assert {tag.d4h_tag_id, tag.title, tag.owner_type, tag.owner_id} ==
             {12, "SRVTC Hours", "Organisation", 40}
  end

  test "a missing owner stays nil" do
    tag = Tag.build(%{"id" => 12, "title" => "Boat"})
    assert {tag.owner_type, tag.owner_id} == {nil, nil}
  end
end
