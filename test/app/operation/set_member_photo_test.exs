defmodule App.Operation.SetMemberPhotoTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Operation.SetMemberPhoto

  @member %Member{id: 7, d4h_member_id: 70}

  test "a new photo's row records its size, never the image" do
    row = SetMemberPhoto.plan(@member, "jpeg bytes")
    assert {row.action, row.d4h_record_id, row.member_id} == {:set_member_photo, 70, 7}
    assert row.new_value == %{"size" => 10}
  end

  test "no photo removes it" do
    assert %{action: :remove_member_photo, d4h_record_id: 70} = SetMemberPhoto.plan(@member, nil)
  end
end
