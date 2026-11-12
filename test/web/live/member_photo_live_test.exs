defmodule Web.MemberPhotoLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.RecordsStub
  alias App.Repo

  defp upload(lv, name, content, type) do
    lv
    |> file_input("#photo-form", :photo, [%{name: name, content: content, type: type}])
    |> render_upload(name)
  end

  describe "on a Records team" do
    setup %{conn: conn} do
      %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
      admin = Repo.get_by!(Member, team_id: team.id, email: user.email)
      %{conn: log_in_user(conn, user), team: team, admin: admin}
    end

    defp stub_ok,
      do: RecordsStub.stub(fn _method, _path, _body -> {200, RecordsStub.member_json(77)} end)

    test "Change photo is in the member's Actions", %{conn: conn, team: team, admin: admin} do
      {:ok, page, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}")
      photo_path = ~p"/teams/#{team}/members/#{admin.id}/photo"
      assert has_element?(page, ~s|#member-actions #member-change-photo[href="#{photo_path}"]|)
    end

    test "a photo goes to Records as a JPEG up to 2400 px, and back to the member's page",
         %{conn: conn, team: team, admin: admin} do
      stub_ok()
      admin |> Ecto.Changeset.change(has_photo: false) |> Repo.update!()
      photo = png_fixture(3200, 2400)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/photo")
      assert has_element?(lv, "#member-photo-none")
      refute has_element?(lv, "#remove-photo")
      upload(lv, "face.png", photo, "image/png")

      {:ok, _page, html} =
        lv |> form("#photo-form") |> render_submit() |> follow_redirect(conn)

      assert html =~ "#{admin.name}: Photo saved."

      path = "/members/#{admin.d4h_member_id}/image"
      assert_received {:records, "PUT", ^path, {:bytes, <<0xFF, 0xD8, _rest::binary>> = jpeg}}
      image = Image.from_binary!(jpeg)
      assert {Image.width(image), Image.height(image)} == {2400, 1800}

      [row] = Repo.all(ChangeSetRow)
      assert {row.action, row.status} == {:set_member_photo, :applied}
      assert row.new_value == %{"size" => byte_size(jpeg)}
      # Set with no download, so an ID card can follow at once (#1012), and a new
      # version, so the page loads the new photo past the one the browser kept.
      saved = Repo.reload!(admin)
      assert saved.has_photo
      assert Member.photo_version(saved) > Member.photo_version(admin)
    end

    test "a team admin removes a photo", %{conn: conn, team: team, admin: admin} do
      stub_ok()
      admin |> Ecto.Changeset.change(has_photo: true) |> Repo.update!()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/photo")

      {:ok, _page, html} =
        lv |> element("#remove-photo") |> render_click() |> follow_redirect(conn)

      assert html =~ "#{admin.name}: Photo removed."
      path = "/members/#{admin.d4h_member_id}/image"
      assert_received {:records, "DELETE", ^path, nil}
      refute Repo.reload!(admin).has_photo
    end

    test "a file that isn't a photo says so, nothing is sent, and the page stays",
         %{conn: conn, team: team, admin: admin} do
      stub_ok()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/photo")
      upload(lv, "face.jpg", "not a photo", "image/jpeg")

      lv |> form("#photo-form") |> render_submit()
      assert has_element?(lv, "#flash-error", "SAR Duty cannot read this photo.")

      refute_received {:records, _method, _path, _body}
      assert Repo.all(ChangeSetRow) == []
    end

    test "saving with no photo selected asks for one", %{conn: conn, team: team, admin: admin} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/photo")
      assert lv |> form("#photo-form") |> render_submit() =~ "Select a photo."
    end

    test "another team's member 404s", %{conn: conn, team: team} do
      other = member_fixture(team_fixture())

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/teams/#{team}/members/#{other.id}/photo")
      end
    end
  end

  describe "on a D4H team" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "d4h_key"}})
      %{conn: log_in_user(conn, user), team: team}
    end

    test "the page has the photo, its original, and Remove photo", %{conn: conn, team: team} do
      member = member_fixture(team, %{has_photo: true})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/photo")

      version = Member.photo_version(member)
      photo = ~p"/teams/#{team}/members/#{member.id}/image?v=#{version}"
      original = ~p"/teams/#{team}/members/#{member.id}/image/original"
      assert has_element?(lv, ~s|#member-photo-image[src="#{photo}"]|)
      assert has_element?(lv, ~s|#download-photo[href="#{original}"]|)
      # Red: it deletes the photo from the team's records.
      assert has_element?(lv, "#remove-photo.btn-danger")
      refute has_element?(lv, "#member-photo-none")
    end

    test "a photo goes to D4H as the member's profile document", %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {200, %{"id" => 99}} end, %{
        "/documents" => [%{"id" => 11}]
      })

      member = member_fixture(team, %{has_photo: false})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/photo")
      upload(lv, "face.png", png_fixture(40, 30), "image/png")

      {:ok, _page, html} =
        lv |> form("#photo-form") |> render_submit() |> follow_redirect(conn)

      assert html =~ "Photo saved."

      assert_received {:records, "POST", "/documents", {:multipart, form}}
      assert form =~ ~s(name="targetResourceId"\r\n\r\n#{member.d4h_member_id})
      assert form =~ ~s(name="profile"\r\n\r\ntrue)
      # The photo it replaces would stay on the member as a plain attachment.
      assert_received {:records, "DELETE", "/documents/11", nil}

      [row] = Repo.all(ChangeSetRow)
      assert {row.action, row.status} == {:set_member_photo, :applied}
      assert Repo.reload!(member).has_photo
    end

    test "Remove photo deletes the member's profile document in D4H", %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {200, %{}} end, %{
        "/documents" => [%{"id" => 11}]
      })

      member = member_fixture(team, %{has_photo: true})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/photo")

      {:ok, _page, html} =
        lv |> element("#remove-photo") |> render_click() |> follow_redirect(conn)

      assert html =~ "Photo removed."
      assert_received {:records, "DELETE", "/documents/11", nil}
      refute Repo.reload!(member).has_photo
    end

    test "D4H's refusal shows in the toast, and the photo stays", %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {403, %{"title" => "Forbidden"}} end)

      member = member_fixture(team, %{has_photo: true})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/photo")
      upload(lv, "face.png", png_fixture(40, 30), "image/png")

      assert lv |> form("#photo-form") |> render_submit() =~ "D4H refused it"
      assert Repo.reload!(member).has_photo
    end
  end
end
