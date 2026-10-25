defmodule App.Adapter.D4H.WhiteboardNoteTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.WhiteboardNote

  test "a team's note" do
    note =
      WhiteboardNote.build(%{
        "id" => 9,
        "text" => "Pager test Sunday at 10:00.",
        "url" => "https://example.com/pager",
        "important" => true,
        "owner" => %{"resourceType" => "Team", "id" => 422},
        "archivedAt" => "2026-10-26T07:00:00.000Z",
        "createdAt" => "2026-10-22T16:00:00.000Z"
      })

    assert note == %WhiteboardNote{
             d4h_whiteboard_note_id: 9,
             text: "Pager test Sunday at 10:00.",
             url: "https://example.com/pager",
             important: true,
             owner_kind: :team,
             archived_at: ~U[2026-10-26 07:00:00Z],
             created_at: ~U[2026-10-22 16:00:00Z]
           }
  end

  test "an organization's note, with no link and no archive time" do
    note =
      WhiteboardNote.build(%{
        "id" => 3,
        "text" => "BCSARA AGM is on November 15.",
        "url" => "",
        "owner" => %{"resourceType" => "Organisation", "id" => 7},
        "archivedAt" => nil,
        "createdAt" => "2026-10-12T16:00:00Z"
      })

    assert note.owner_kind == :organization
    assert note.url == nil
    assert note.important == false
    assert note.archived_at == nil
  end

  # cspell:ignore nbsp -- the HTML entity for a non-breaking space
  test "HTML from D4H becomes plain text" do
    note =
      WhiteboardNote.build(%{
        "id" => 1,
        "text" => "<p><b>Dues</b> &amp; fees are due.</p><p>Pay&nbsp;at the hall.</p>",
        "owner" => %{"resourceType" => "Team", "id" => 1}
      })

    assert note.text == "Dues & fees are due. Pay at the hall."
  end
end
