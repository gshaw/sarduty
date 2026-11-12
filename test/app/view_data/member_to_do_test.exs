defmodule App.ViewData.MemberToDoTest do
  use ExUnit.Case, async: true

  alias App.ViewData.MemberToDo

  @card %{id: 1}

  defp row(status, title, days_left),
    do: %{status: status, award: %{qualification: %{title: title}}, days_left: days_left}

  defp keys(items), do: Enum.map(items, & &1.key)

  test "the card stays until it's in Wallet, and a member with no card has no item" do
    assert keys(MemberToDo.items(@card, false, [])) == [:card]
    assert MemberToDo.items(@card, true, []) == []
    assert MemberToDo.items(nil, false, []) == []
  end

  test "each qualification expiring within 60 days, with its days left" do
    rows = [
      row(:expiring, "First Aid", 41),
      row(:expiring, "Radio", 1),
      row(:current, "Swiftwater", 132),
      row(:expired, "Rope", -750)
    ]

    assert [%{days: 41}, %{days: 1}] = MemberToDo.items(nil, false, rows)
  end

  test "a declined photo is one item, and none without one (#1029)" do
    photo = %{id: 3, decline_reason: :dark}

    assert [%{key: :declined_photo, photo: ^photo}] =
             MemberToDo.items(nil, false, [], declined_photo: photo)

    assert MemberToDo.items(nil, false, [], declined_photo: nil) == []

    # An ask for a photo (#1030) comes first of the two.
    asked = %{ask: %App.Model.PhotoAsk{id: 1}, asked_by: "Alex Chen"}

    assert [%{key: :photo_ask, asked_by: "Alex Chen"}, %{key: :declined_photo}] =
             MemberToDo.items(nil, false, [], declined_photo: photo, photo_ask: asked)

    assert MemberToDo.items(nil, false, [], photo_ask: nil) == []
  end

  test "items come card, then qualifications" do
    rows = [row(:expiring, "First Aid", 41)]
    items = MemberToDo.items(@card, false, rows)
    assert keys(items) == [:card, :qualification]
  end

  test "declined chores are one item until the member deletes them" do
    chores = [
      %{status: :declined, id: 1},
      %{status: :accepted, id: 2},
      %{status: :declined, id: 3}
    ]

    assert [%{key: :declined_chores, chores: [%{id: 1}, %{id: 3}]}] =
             MemberToDo.items(nil, false, [], chores: chores)

    assert MemberToDo.items(nil, false, [], chores: [%{status: :waiting, id: 4}]) ==
             []
  end

  test "a waiting certificate takes its qualification off; a declined one is an item (#493)" do
    rows = [
      %{status: :expiring, award: %{qualification_id: 7}, days_left: 19},
      %{status: :expiring, award: %{qualification_id: 8}, days_left: 30}
    ]

    certificates = [
      %{status: :waiting, qualification_id: 7, id: 1},
      %{status: :declined, qualification_id: 8, id: 2}
    ]

    assert [%{key: :qualification, award: %{qualification_id: 8}}, item] =
             MemberToDo.items(nil, false, rows, certificates: certificates)

    assert %{key: :declined_certificates, certificates: [%{id: 2}]} = item
  end
end
