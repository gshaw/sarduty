defmodule App.Operation.SaveWhiteboardNoteTest do
  use App.DataCase

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.Adapter.D4H
  alias App.Model.ChangeSet
  alias App.Model.WhiteboardNote
  alias App.Operation.SaveWhiteboardNote
  alias App.ViewModel.WhiteboardNoteFormViewModel

  describe "archived_at/2" do
    test "is the start of the day after the last day, in the team's zone" do
      assert SaveWhiteboardNote.archived_at(~D[2026-10-25], "America/Toronto") ==
               ~U[2026-10-26 04:00:00Z]
    end

    # tzdata keeps Vancouver on UTC-7 from November 2026, so Toronto has the change.
    test "follows a daylight saving change" do
      assert SaveWhiteboardNote.archived_at(~D[2026-10-31], "America/Toronto") ==
               ~U[2026-11-01 04:00:00Z]

      assert SaveWhiteboardNote.archived_at(~D[2026-11-01], "America/Toronto") ==
               ~U[2026-11-02 05:00:00Z]
    end
  end

  describe "refused_text/2" do
    test "names the service, and Records' titles read as fixes" do
      d4h = team_fixture()
      records = team_fixture(%{d4h_api_host: D4H.records_host()})

      assert SaveWhiteboardNote.refused_text(d4h, "Bad Request. text is too long") ==
               "D4H did not take the note: Bad Request. text is too long. Try again."

      assert SaveWhiteboardNote.refused_text(records, "Enter a note of 3 to 140 characters.") ==
               "SAR Duty Records did not take the note: Enter a note of 3 to 140 characters."

      assert SaveWhiteboardNote.refused_text(d4h, "D4H did not answer. Try again.") ==
               "D4H did not answer. Try again."
    end
  end

  # D4H's answer to each write, telling the test what it was sent.
  defp stub_d4h(status \\ 200) do
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:d4h, conn.method, conn.request_path, body != "" && Jason.decode!(body)})

      if status == 200 do
        Req.Test.json(conn, %{
          "id" => 77,
          "text" => "Answer",
          "owner" => %{"resourceType" => "Team"}
        })
      else
        conn
        |> Plug.Conn.put_status(status)
        |> Req.Test.json(%{"title" => "Unprocessable Entity", "detail" => "text is too long"})
      end
    end)
  end

  setup do
    team = team_fixture(%{d4h_access_key: "key", timezone: "America/Toronto"})
    %{team: team, user: AccountsFixtures.user_fixture()}
  end

  test "post sends one row and saves the note here", %{team: team, user: user} do
    stub_d4h()

    form = %WhiteboardNoteFormViewModel{
      text: "Pager test Sunday.",
      url: nil,
      important: true,
      until: ~D[2026-10-31]
    }

    assert {:ok, note} =
             SaveWhiteboardNote.post(team, user, form, ~U[2026-10-24 18:00:00.000000Z])

    path = "/v3/team/#{team.d4h_team_id}/whiteboard"

    assert_received {:d4h, "POST", ^path,
                     %{
                       "text" => "Pager test Sunday.",
                       "important" => true,
                       "archivedAt" => "2026-11-01T04:00:00Z"
                     } = body}

    refute Map.has_key?(body, "url")
    assert %{d4h_whiteboard_note_id: 77, owner_kind: :team, text: "Pager test Sunday."} = note
    assert note.archived_at == ~U[2026-11-01 04:00:00Z]
    assert [%ChangeSet{source: :whiteboard}] = Repo.all(ChangeSet)
  end

  test "change, archive, and delete each send one row and change the copy here", ctx do
    %{team: team, user: user} = ctx
    note = whiteboard_note_fixture(team, %{d4h_whiteboard_note_id: 77})
    path = "/v3/team/#{team.d4h_team_id}/whiteboard/77"
    stub_d4h()

    form = %WhiteboardNoteFormViewModel{
      text: "Pager test moved.",
      url: "https://example.com",
      until: ~D[2026-11-05]
    }

    assert {:ok, changed} = SaveWhiteboardNote.change(team, user, note, form)

    assert_received {:d4h, "PATCH", ^path,
                     %{"text" => "Pager test moved.", "url" => "https://example.com"}}

    assert changed.text == "Pager test moved."

    now = ~U[2026-10-24 18:00:00.123456Z]
    assert {:ok, archived} = SaveWhiteboardNote.archive(team, user, changed, now)
    assert_received {:d4h, "PATCH", ^path, %{"archivedAt" => "2026-10-24T18:00:00Z"} = body}
    assert map_size(body) == 1
    assert archived.archived_at == ~U[2026-10-24 18:00:00Z]

    assert {:ok, _deleted} = SaveWhiteboardNote.delete(team, user, archived)
    assert_received {:d4h, "DELETE", ^path, false}
    refute Repo.get(WhiteboardNote, note.id)
    assert Repo.aggregate(ChangeSet, :count) == 3
  end

  test "a refusal shows D4H's title and changes nothing here", %{team: team, user: user} do
    note = whiteboard_note_fixture(team)
    stub_d4h(422)

    assert {:error, text} = SaveWhiteboardNote.archive(team, user, note)
    assert text == "D4H did not take the note: Unprocessable Entity. text is too long. Try again."
    assert Repo.reload(note) == note
  end

  test "an organization's note and another team's are never sent", %{team: team, user: user} do
    org_note = whiteboard_note_fixture(team, %{owner_kind: :organization})
    other = whiteboard_note_fixture(team_fixture())

    assert {:error, _text} = SaveWhiteboardNote.archive(team, user, org_note)
    assert {:error, _text} = SaveWhiteboardNote.delete(team, user, other)
    assert Repo.all(ChangeSet) == []
  end
end
