defmodule Web.WhiteboardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  defp archived_note(team, attrs \\ %{}) do
    whiteboard_note_fixture(
      team,
      Map.merge(
        %{
          text: "Dues are due by October 15.",
          archived_at: DateTime.utc_now(:second) |> DateTime.add(-3, :day),
          d4h_created_at: DateTime.utc_now(:second) |> DateTime.add(-30, :day)
        },
        attrs
      )
    )
  end

  describe "the Whiteboard page" do
    test "a member reads the live notes and the archived ones", %{conn: conn} do
      %{team: team, user: user} = member_with_login_fixture()
      live_note = whiteboard_note_fixture(team)
      old = archived_note(team)
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard")
      assert has_element?(lv, "#whiteboard-switch", "On the whiteboard")
      assert has_element?(lv, "#whiteboard-notes #whiteboard-note-#{live_note.id}")
      refute has_element?(lv, "#whiteboard-note-#{old.id}")

      lv |> element("#whiteboard-view-archived") |> render_click()
      assert_patch(lv, ~p"/teams/#{team}/whiteboard?view=archived")
      assert has_element?(lv, "#whiteboard-note-#{old.id}", "Dues are due")
      refute has_element?(lv, "#whiteboard-note-#{live_note.id}")
    end

    test "each list says when it is empty", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard")
      assert has_element?(lv, "#whiteboard-empty", "Post one for everyone on the team to read.")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard?view=archived")
      assert has_element?(lv, "#whiteboard-empty", "No archived notes")
    end

    test "is not found with the module off", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      team |> Ecto.Changeset.change(whiteboard_enabled: false) |> Repo.update!()

      assert_raise Web.Status.NotFound, fn ->
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/whiteboard")
      end
    end
  end

  describe "posting and changing notes" do
    # D4H takes each write and answers with note 77, telling the test what it was sent.
    defp stub_d4h do
      test = self()

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:d4h, conn.method, conn.request_path, body})
        Req.Test.json(conn, %{"id" => 77, "owner" => %{"resourceType" => "Team"}})
      end)
    end

    defp admin_conn(conn) do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "key"}})
      {log_in_user(conn, user), team}
    end

    test "a member gets no form and no buttons", %{conn: conn} do
      %{team: team, user: user} = member_with_login_fixture()
      note = whiteboard_note_fixture(team)
      old = archived_note(team)
      conn = log_in_user(conn, user)

      for path <- [
            ~p"/teams/#{team}/whiteboard/new",
            ~p"/teams/#{team}/whiteboard/#{note.id}/edit"
          ] do
        assert_raise Web.Status.NotFound, fn -> live(conn, path) end
      end

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard")
      refute has_element?(lv, "#whiteboard-post")
      refute has_element?(lv, "#whiteboard-archive-#{note.id}")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard?view=archived")
      refute has_element?(lv, "#whiteboard-again-#{old.id}")
    end

    test "a team admin posts a note and is back on the Dashboard", %{conn: conn} do
      {conn, team} = admin_conn(conn)
      stub_d4h()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard/new")

      assert lv |> form("#whiteboard-note-form", note: %{text: "Hi"}) |> render_change() =~
               "Enter a note of 3 to 140 characters"

      until = Date.utc_today() |> Date.add(10) |> Date.to_iso8601()

      lv
      |> form("#whiteboard-note-form", note: %{text: "Pager test Sunday.", until: until})
      |> render_submit()

      assert_redirect(lv, ~p"/teams/#{team}")
      assert_received {:d4h, "POST", _path, body}
      assert body =~ "Pager test Sunday."

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      assert has_element?(lv, "#whiteboard", "Pager test Sunday.")
    end

    test "Post again fills the form from an archived note", %{conn: conn} do
      {conn, team} = admin_conn(conn)
      old = archived_note(team, %{url: "https://example.com/dues", important: true})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard?view=archived")
      lv |> element("#whiteboard-again-#{old.id}") |> render_click()
      {path, _flash} = assert_redirect(lv)
      assert path == ~p"/teams/#{team}/whiteboard/new?from=#{old.id}"

      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "#whiteboard-note-form textarea", "Dues are due by October 15.")
      assert has_element?(lv, ~s{#whiteboard-note-form input[value="https://example.com/dues"]})
    end

    test "archive takes a note off the card, and delete removes it", %{conn: conn} do
      {conn, team} = admin_conn(conn)
      note = whiteboard_note_fixture(team, %{d4h_whiteboard_note_id: 77})
      stub_d4h()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      lv |> element("#whiteboard-archive-#{note.id}") |> render_click()
      assert_received {:d4h, "PATCH", _path, _body}
      refute has_element?(lv, "#whiteboard-note-#{note.id}")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard?view=archived")
      lv |> element("#whiteboard-delete-#{note.id}") |> render_click()
      assert_received {:d4h, "DELETE", _path, _body}
      refute has_element?(lv, "#whiteboard-note-#{note.id}")
    end

    test "Change note saves, and deletes from its foot", %{conn: conn} do
      {conn, team} = admin_conn(conn)
      note = whiteboard_note_fixture(team, %{d4h_whiteboard_note_id: 77})
      stub_d4h()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard/#{note.id}/edit")
      assert has_element?(lv, "h1", "Change note")

      lv |> form("#whiteboard-note-form", note: %{text: "Pager test moved."}) |> render_submit()
      assert_redirect(lv, ~p"/teams/#{team}")
      assert Repo.reload(note).text == "Pager test moved."

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard/#{note.id}/edit")
      lv |> element("#whiteboard-note-delete-button") |> render_click()
      assert_redirect(lv, ~p"/teams/#{team}")
      refute Repo.reload(note)
    end

    test "an organization's note has Post again only", %{conn: conn} do
      {conn, team} = admin_conn(conn)
      live_note = whiteboard_note_fixture(team, %{owner_kind: :organization})
      old = archived_note(team, %{owner_kind: :organization})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      assert has_element?(lv, "#whiteboard-note-#{live_note.id}")
      refute has_element?(lv, "#whiteboard-change-#{live_note.id}")
      refute has_element?(lv, "#whiteboard-archive-#{live_note.id}")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/whiteboard?view=archived")
      assert has_element?(lv, "#whiteboard-again-#{old.id}")
      refute has_element?(lv, "#whiteboard-delete-#{old.id}")

      assert_raise Web.Status.NotFound, fn ->
        live(conn, ~p"/teams/#{team}/whiteboard/#{live_note.id}/edit")
      end
    end
  end
end
