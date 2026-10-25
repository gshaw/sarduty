defmodule App.Model.WhiteboardNoteTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.WhiteboardNote

  test "live notes come Important first, then the newest, and archived ones the newest first" do
    team = team_fixture()
    now = ~U[2026-10-24 18:00:00Z]

    whiteboard_note_fixture(team, %{
      text: "Old",
      archived_at: ~U[2026-10-01 07:00:00Z],
      d4h_created_at: ~U[2026-09-01 00:00:00Z]
    })

    whiteboard_note_fixture(team, %{
      text: "Older",
      archived_at: ~U[2026-09-01 07:00:00Z],
      d4h_created_at: ~U[2026-08-01 00:00:00Z]
    })

    whiteboard_note_fixture(team, %{
      text: "Newest",
      archived_at: ~U[2026-11-01 07:00:00Z],
      d4h_created_at: ~U[2026-10-23 00:00:00Z]
    })

    whiteboard_note_fixture(team, %{
      text: "Important",
      important: true,
      archived_at: ~U[2026-11-01 07:00:00Z],
      d4h_created_at: ~U[2026-10-20 00:00:00Z]
    })

    whiteboard_note_fixture(team, %{
      text: "Never archives",
      archived_at: nil,
      d4h_created_at: ~U[2026-10-21 00:00:00Z]
    })

    # Archived on the second the page asks.
    whiteboard_note_fixture(team, %{
      text: "Just archived",
      archived_at: now,
      d4h_created_at: ~U[2026-10-01 00:00:00Z]
    })

    whiteboard_note_fixture(team_fixture(), %{text: "Another team's"})

    assert team |> WhiteboardNote.live(now) |> Enum.map(& &1.text) ==
             ["Important", "Newest", "Never archives"]

    assert WhiteboardNote.archived(team, now).entries |> Enum.map(& &1.text) ==
             ["Just archived", "Old", "Older"]

    assert WhiteboardNote.counts(team, now) == %{live: 3, archived: 3}
  end

  test "a note's last day is the day before it archives, in the team's zone" do
    note = %WhiteboardNote{archived_at: ~U[2026-10-26 04:00:00Z]}
    assert WhiteboardNote.last_day(note, "America/Toronto") == ~D[2026-10-25]
    assert WhiteboardNote.last_day(note, "Etc/UTC") == ~D[2026-10-26]
    assert WhiteboardNote.last_day(%WhiteboardNote{}, "Etc/UTC") == nil
  end

  describe "for_dashboard/1" do
    defp note(text, important \\ false), do: %WhiteboardNote{text: text, important: important}
    defp texts({shown, more}), do: {Enum.map(shown, & &1.text), more}

    test "the Important notes, at most 2, and the rest left over" do
      notes = [note("A", true), note("B", true), note("C", true), note("D"), note("E")]
      assert notes |> WhiteboardNote.for_dashboard() |> texts() == {["A", "B"], 3}

      assert [note("A", true), note("D")] |> WhiteboardNote.for_dashboard() |> texts() ==
               {["A"], 1}
    end

    test "the newest alone when none is Important, and nothing with no notes" do
      assert [note("D"), note("E")] |> WhiteboardNote.for_dashboard() |> texts() == {["D"], 1}
      assert [note("D")] |> WhiteboardNote.for_dashboard() |> texts() == {["D"], 0}
      assert WhiteboardNote.for_dashboard([]) == {[], 0}
    end
  end
end
