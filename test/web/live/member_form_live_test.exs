defmodule Web.MemberFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.RecordsStub
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
    admin = Repo.get_by!(Member, team_id: team.id, email: user.email)
    %{conn: log_in_user(conn, user), team: team, admin: admin}
  end

  defp stub_ok,
    do: RecordsStub.stub(fn _method, _path, _body -> {200, RecordsStub.member_json(77)} end)

  test "a team admin adds a member through Records", %{conn: conn, team: team} do
    stub_ok()
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/members")
    assert has_element?(list, "#member-add")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/new")
    assert has_element?(lv, ~s|#member-cancel[href="#{~p"/teams/#{team}/members"}"]|)

    {:ok, _lv, html} =
      lv
      |> form("#member-form",
        form: %{name: "Casey New", email: "Casey@Example.com", joined_on: "2026-01-15"}
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Saved Casey New."

    assert_received {:records, "POST", "/members", body}
    assert body["name"] == "Casey New"
    assert body["email"] == "casey@example.com"
    assert body["permission"] == 2
    assert body["startsAt"] == "2026-01-15T08:00:00Z"

    change_set = Repo.get_by!(ChangeSet, team_id: team.id, source: :edit)

    assert [%ChangeSetRow{action: :create_member, status: :applied, d4h_record_id: 77}] =
             Repo.preload(change_set, :rows).rows
  end

  test "the only team admin cannot stop being one or leave", %{
    conn: conn,
    team: team,
    admin: admin
  } do
    stub_ok()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/edit")

    html = lv |> form("#member-form", form: %{team_admin: "false"}) |> render_submit()
    assert html =~ "Make another member a team admin first."

    assert lv |> element("#member-retire-button") |> render_click() =~
             "Make another member a team admin first."

    refute_received {:records, _method, _path, _body}
  end

  test "a change sends only what changed, and leaving is a retire",
       %{conn: conn, team: team, admin: admin} do
    stub_ok()
    manager_fixture(team)

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}")
    assert has_element?(page, "#member-actions #member-edit")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/edit")
    assert has_element?(lv, ~s|#member-cancel[href="#{~p"/teams/#{team}/members/#{admin.id}"}"]|)
    lv |> form("#member-form", form: %{position: "Training Officer"}) |> render_submit()

    path = "/members/#{admin.d4h_member_id}"
    assert_received {:records, "PATCH", ^path, %{"position" => "Training Officer"} = body}
    assert map_size(body) == 1

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/edit")
    lv |> element("#member-retire-button") |> render_click()

    retire = "/members/#{admin.d4h_member_id}/retire"
    assert_received {:records, "PATCH", ^retire, %{"direction" => "RETIRE"}}
  end

  test "a retired member is marked as rejoined", %{conn: conn, team: team} do
    stub_ok()
    member = member_fixture(team, %{d4h_status: "RETIRED", left_at: ~U[2026-01-01 08:00:00Z]})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")
    lv |> element("#member-rejoin") |> render_click()

    retire = "/members/#{member.d4h_member_id}/retire"
    assert_received {:records, "PATCH", ^retire, %{"direction" => "UNRETIRE"}}
  end

  test "Records' refusal shows as the error", %{conn: conn, team: team} do
    RecordsStub.stub(fn _method, _path, _body -> {400, %{"title" => "Enter a shorter name."}} end)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/new")

    html =
      lv
      |> form("#member-form", form: %{name: "Casey New", joined_on: "2026-01-15"})
      |> render_submit()

    assert html =~ "Enter a shorter name."
  end

  test "a team admin uploads a photo, which goes to Records as a JPEG and is not kept here",
       %{conn: conn, team: team, admin: admin} do
    stub_ok()
    admin |> Ecto.Changeset.change(has_photo: false) |> Repo.update!()
    photo = png_fixture(3200, 2400)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/edit")

    lv
    |> file_input("#photo-form", :photo, [%{name: "face.png", content: photo, type: "image/png"}])
    |> render_upload("face.png")

    assert lv |> form("#photo-form") |> render_submit() =~ "Photo saved."

    path = "/members/#{admin.d4h_member_id}/image"
    assert_received {:records, "PUT", ^path, {:bytes, <<0xFF, 0xD8, _rest::binary>> = jpeg}}
    image = Image.from_binary!(jpeg)
    assert {Image.width(image), Image.height(image)} == {2400, 1800}

    [row] = Repo.all(ChangeSetRow)
    assert {row.action, row.status} == {:set_member_photo, :applied}
    assert row.new_value == %{"size" => byte_size(jpeg)}
    # Set with no download, so an ID card can follow at once (#1012).
    assert Repo.reload!(admin).has_photo
  end

  test "a team admin removes a photo", %{conn: conn, team: team, admin: admin} do
    stub_ok()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/edit")

    assert lv |> element("#remove-photo") |> render_click() =~ "Photo removed."

    path = "/members/#{admin.d4h_member_id}/image"
    assert_received {:records, "DELETE", ^path, nil}
    refute Repo.reload!(admin).has_photo
  end

  test "a file that isn't a photo says so, and nothing is sent",
       %{conn: conn, team: team, admin: admin} do
    stub_ok()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/edit")

    lv
    |> file_input("#photo-form", :photo, [
      %{name: "face.jpg", content: "not a photo", type: "image/jpeg"}
    ])
    |> render_upload("face.jpg")

    lv |> form("#photo-form") |> render_submit()
    assert has_element?(lv, "#flash-error", "SAR Duty cannot read this photo.")

    refute_received {:records, _method, _path, _body}
    assert Repo.all(ChangeSetRow) == []
  end

  test "saving with no photo selected asks for one", %{conn: conn, team: team, admin: admin} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/edit")
    assert lv |> form("#photo-form") |> render_submit() =~ "Select a photo."
  end

  test "a name is needed, and the error summary lists it", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/new")
    lv |> form("#member-form", form: %{name: "", joined_on: ""}) |> render_submit()

    assert has_element?(lv, "#member-form .error-summary", "Enter the member's name.")
  end

  test "another team's member 404s", %{conn: conn, team: team} do
    other = member_fixture(team_fixture())

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/teams/#{team}/members/#{other.id}/edit")
    end
  end

  describe "on a D4H team" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "d4h_key"}})
      %{conn: log_in_user(conn, user), team: team}
    end

    test "there is no Add member, and adding 404s", %{conn: conn, team: team} do
      {:ok, list, _html} = live(conn, ~p"/teams/#{team}/members")
      refute has_element?(list, "#member-add")
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/members/new") end
    end

    test "Change member has the details and photo D4H takes, without access or leaving",
         %{conn: conn, team: team} do
      member = member_fixture(team, %{position: "MIT", has_photo: true})
      member_fixture(team, %{position: "GSTL"})
      member_fixture(team, %{position: "MIT"})

      {:ok, page, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}")
      assert has_element?(page, "#member-actions #member-edit")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")
      # The combobox with free text: the text box is the field, the select only suggests.
      assert has_element?(lv, "#form_position-combobox[data-free-text] #form_position-clear")
      assert has_element?(lv, "input#form_position[name='form[position]'][value=MIT]")
      refute has_element?(lv, "#form_position-select[name]")
      assert has_element?(lv, "#form_position-select option:nth-child(2)[value=MIT]")
      assert has_element?(lv, "#form_position-select option[value=GSTL]")
      refute has_element?(lv, "#form_team_admin")
      assert has_element?(lv, "#member-photo #save-photo")
      assert has_element?(lv, "#member-photo #remove-photo")

      original = ~p"/teams/#{team}/members/#{member.id}/image/original?v=0"
      assert has_element?(lv, ~s|#download-photo[href="#{original}"]|)
      refute has_element?(lv, "#member-retire")
    end

    test "a photo goes to D4H as the member's profile document",
         %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {200, %{"id" => 99}} end, %{
        "/documents" => [%{"id" => 11}]
      })

      member = member_fixture(team, %{has_photo: false})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")

      lv
      |> file_input("#photo-form", :photo, [
        %{name: "face.png", content: png_fixture(40, 30), type: "image/png"}
      ])
      |> render_upload("face.png")

      assert lv |> form("#photo-form") |> render_submit() =~ "Photo saved."

      assert_received {:records, "POST", "/documents", {:multipart, form}}
      assert form =~ ~s(name="targetResourceId"\r\n\r\n#{member.d4h_member_id})
      assert form =~ ~s(name="profile"\r\n\r\ntrue)
      # The photo it replaces would stay on the member as a plain attachment.
      assert_received {:records, "DELETE", "/documents/11", nil}

      [row] = Repo.all(ChangeSetRow)
      assert {row.action, row.status} == {:set_member_photo, :applied}
      assert Repo.reload!(member).has_photo
    end

    test "Remove photo deletes the member's profile document in D4H",
         %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {200, %{}} end, %{
        "/documents" => [%{"id" => 11}]
      })

      member = member_fixture(team, %{has_photo: true})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")

      assert has_element?(lv, "#download-photo")
      assert lv |> element("#remove-photo") |> render_click() =~ "Photo removed."
      assert_received {:records, "DELETE", "/documents/11", nil}
      refute Repo.reload!(member).has_photo
      # Nothing left to download.
      refute has_element?(lv, "#download-photo")
    end

    test "D4H's refusal shows in the toast, and the photo stays", %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {403, %{"title" => "Forbidden"}} end)

      member = member_fixture(team, %{has_photo: true})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")

      lv
      |> file_input("#photo-form", :photo, [
        %{name: "face.png", content: png_fixture(40, 30), type: "image/png"}
      ])
      |> render_upload("face.png")

      assert lv |> form("#photo-form") |> render_submit() =~ "D4H refused it"
      assert Repo.reload!(member).has_photo
    end

    test "saving sends D4H only what changed", %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {200, RecordsStub.member_json(77)} end)

      member = member_fixture(team, %{d4h_status: "OPERATIONAL"})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")

      lv
      |> form("#member-form", form: %{position: "Search Manager", ref_id: "SF 12"})
      |> render_submit()

      path = "/members/#{member.d4h_member_id}"
      assert_received {:records, "PATCH", ^path, body}
      assert body == %{"position" => "Search Manager", "ref" => "SF 12"}

      [row] = Repo.all(ChangeSetRow)
      assert {row.action, row.status, row.member_id} == {:update_member, :applied, member.id}
    end
  end
end
