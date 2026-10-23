defmodule Service.ChoreEventTextTest do
  use ExUnit.Case, async: true

  alias App.Model.Chore
  alias App.Model.Member
  alias Service.ChoreEventText

  test "the title names the category and the month" do
    assert ChoreEventText.title("Equipment maintenance", ~D[2026-10-01]) ==
             "Chores: Equipment maintenance, October 2026"
  end

  test "the description lists members by name and their chores by date, with totals" do
    sam = %Member{id: 2, name: "Sam Rivera"}
    avery = %Member{id: 1, name: "Avery Chen"}

    chores = [
      %Chore{id: 3, member: sam, date: ~D[2026-10-14], minutes: 60, description: "Truck 1 wash"},
      %Chore{
        id: 1,
        member: avery,
        date: ~D[2026-10-06],
        minutes: 180,
        description: "Rope inspection"
      },
      %Chore{id: 2, member: sam, date: ~D[2026-10-07], minutes: 60, description: "Truck 1 wash"}
    ]

    assert ChoreEventText.description(chores) ==
             "<p><i>Made by SAR Duty from accepted chores. Change them in SAR Duty: edits here are replaced.</i></p>" <>
               "<p><b>Avery Chen</b>: 3 hours</p><ul><li>Oct 6: Rope inspection, 3 hours</li></ul>" <>
               "<p><b>Sam Rivera</b>: 2 hours</p><ul><li>Oct 7: Truck 1 wash, 1 hour</li>" <>
               "<li>Oct 14: Truck 1 wash, 1 hour</li></ul>" <>
               "<p>2 members, 3 chores, 5 hours.</p>"
  end
end
