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
end
