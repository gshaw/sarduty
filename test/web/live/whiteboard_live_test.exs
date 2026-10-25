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
end
