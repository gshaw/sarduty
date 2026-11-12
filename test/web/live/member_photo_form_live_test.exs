defmodule Web.MemberPhotoFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.D4H
  alias App.Model.ChangeSetRow
  alias App.RecordsStub
  alias App.Repo

  # Add a photo (#1028): a team admin takes or selects a member's photo, places it, and
  # saves it, on a D4H team and on a Records team.
  setup %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{team: %{photos_enabled: true, d4h_access_key: "team-key"}})

    riley = member_fixture(team, %{name: "Riley Okafor", has_photo: false})
    %{conn: log_in_user(conn, user), team: team, riley: riley}
  end

  defp stub_ok, do: RecordsStub.stub(&reply/3)

  # D4H answers a photo with its document, Records with the member.
  defp reply(_method, "/documents", _body),
    do: {200, %{"id" => 9, "targetResource" => %{"id" => 70}}}

  defp reply(_method, _path, _body), do: {200, RecordsStub.member_json(77)}

  defp add_path(team, member), do: ~p"/teams/#{team}/photos/members/new?#{[member: member.id]}"

  defp pick(lv, bytes, name \\ "face.png") do
    lv
    |> file_input("#photo-form", :photo, [%{name: name, content: bytes, type: "image/png"}])
    |> render_upload(name)
  end

  defp size(bytes) do
    image = Image.from_binary!(bytes)
    {Image.width(image), Image.height(image)}
  end

  test "opens for the member with the guide, then places the photo picked", %{
    conn: conn,
    team: team,
    riley: riley
  } do
    {:ok, lv, _html} = live(conn, add_path(team, riley))

    assert has_element?(lv, ~s|.breadcrumbs a[href="#{~p"/teams/#{team}/photos"}"]|, "Photos")

    assert has_element?(
             lv,
             "#photo-lead",
             "It becomes Riley Okafor's photo, and their ID card shows it."
           )

    refute has_element?(lv, "#photo-member")

    # What works: one good example and 4 rules. What does not: 5 examples.
    assert has_element?(lv, ~s|#photo-guide-good img[src*="photo-guide-good"]|)

    assert lv
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.find("#photo-guide-good li")
           |> length() == 4

    assert has_element?(lv, "#photo-guide-good li", "A plain, light wall behind you")

    assert lv
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.find("#photo-guide-bad > li")
           |> length() == 5

    assert has_element?(lv, "#photo-guide-bad li", "Busy background")

    # Both buttons open the one input, which takes images only.
    assert has_element?(lv, "#photo-take[data-photo-pick=camera]", "Take a photo")
    assert has_element?(lv, "#photo-select[data-photo-pick=file]", "Select a photo")
    assert has_element?(lv, ~s|#photo-pick input[type=file][accept="image/*"]|)
    refute has_element?(lv, "#photo-save")
    # Cancel goes back to the member's ID Card tab, where saving lands too.
    card = ~p"/teams/#{team}/members/#{riley.id}/card"
    assert has_element?(lv, ~s|#photo-cancel[href="#{card}"]|, "Cancel")

    pick(lv, png_fixture(800, 600))

    # The photo comes back as a JPEG the browser can show, to place under the oval.
    assert has_element?(lv, ~s|#photo-placed .photo-place img[src^="data:image/jpeg;base64,"]|)
    assert has_element?(lv, "#photo-placed .photo-place-oval")
    assert has_element?(lv, "#photo-place-hint", "Move or zoom it so the face fills the oval.")
    for tool <- ~w(rotate zoom-out zoom-in), do: assert(has_element?(lv, "#photo-#{tool}"))
    assert has_element?(lv, "#photo-save", "Save photo")
    refute has_element?(lv, "#photo-pick")

    lv |> element("#photo-another", "Take another") |> render_click()
    assert has_element?(lv, "#photo-pick")
    refute has_element?(lv, "#photo-placed")
  end

  test "Save photo sends a D4H team's as the member's profile document, and the ID Card tab shows it",
       %{conn: conn, team: team, riley: riley} do
    stub_ok()

    {:ok, card, _html} = live(conn, ~p"/teams/#{team}/members/#{riley.id}/card")
    assert has_element?(card, "#no-photo", "Riley Okafor has no photo. An ID card needs one.")
    assert has_element?(card, ~s|#add-photo[href="#{add_path(team, riley)}"]|, "Add a photo")
    refute has_element?(card, "#issue")

    {:ok, lv, _html} = live(conn, add_path(team, riley))
    pick(lv, png_fixture(800, 600))

    {:ok, card, html} =
      lv
      |> form("#photo-form")
      |> render_submit(%{
        "photo" => %{"turns" => "1", "x" => "0.5", "y" => "0.4", "side" => "0.5"}
      })
      |> follow_redirect(conn, ~p"/teams/#{team}/members/#{riley.id}/card")

    assert html =~ "Photo saved."

    assert_received {:records, "POST", "/documents", {:multipart, body}}
    assert body =~ ~s|name="profile"\r\n\r\ntrue|
    assert body =~ ~s|name="targetResourceType"\r\n\r\nMember|
    assert body =~ ~s|name="targetResourceId"\r\n\r\n#{riley.d4h_member_id}|
    assert body =~ ~s|name="title"\r\n\r\nPhoto|
    assert body =~ ~s|filename="photo.jpg"|

    [row] = Repo.all(ChangeSetRow)
    assert {row.action, row.status, row.member_id} == {:set_member_photo, :applied, riley.id}
    assert row.d4h_record_id == riley.d4h_member_id
    assert is_integer(row.new_value["size"])

    # Set with no download, and its time versions the photo's URL.
    riley = Repo.reload!(riley)
    assert riley.has_photo
    assert %DateTime{} = riley.photo_changed_at

    refute has_element?(card, "#no-photo")
    version = DateTime.to_unix(riley.photo_changed_at)
    image = ~p"/teams/#{team}/members/#{riley.id}/image?#{[v: version]}"
    assert has_element?(card, ~s|#member-head img[src="#{image}"]|)

    assert has_element?(
             card,
             ~s|#member-actions-change-photo[href="#{add_path(team, riley)}"]|,
             "Change photo"
           )
  end

  test "a Records team's photo still goes as the image: the placed square, as a JPEG", %{
    conn: conn
  } do
    %{user: user, team: team} =
      records_team_with_user_fixture(%{d4h_access_key: "sdr_key", photos_enabled: true})

    member = member_fixture(team, %{name: "Casey New", has_photo: false})
    stub_ok()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(add_path(team, member))
    pick(lv, png_fixture(800, 600))

    lv
    |> form("#photo-form")
    |> render_submit(%{"photo" => %{"turns" => "0", "x" => "0.5", "y" => "0.5", "side" => "0.5"}})

    path = "/members/#{member.d4h_member_id}/image"
    assert_received {:records, "PUT", ^path, {:bytes, <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg}}
    assert size(jpeg) == {300, 300}
    assert Repo.reload!(member).has_photo
  end

  test "with no member in the URL, a Member box lists the current members", %{
    conn: conn,
    team: team,
    riley: riley
  } do
    stub_ok()
    retired = member_fixture(team, %{name: "Old Timer", left_at: ~U[2020-01-01 00:00:00Z]})
    truck = member_fixture(team, %{name: "Truck 1", not_a_person: true})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos/members/new")

    assert has_element?(
             lv,
             ~s|select[name=member_id] option[value="#{riley.id}"]|,
             "Riley Okafor"
           )

    refute has_element?(lv, ~s|select[name=member_id] option[value="#{retired.id}"]|)
    refute has_element?(lv, ~s|select[name=member_id] option[value="#{truck.id}"]|)

    assert has_element?(
             lv,
             "#photo-lead",
             "It becomes the member's photo, and their ID card shows it."
           )

    pick(lv, png_fixture(600, 600))
    html = lv |> form("#photo-form") |> render_submit()
    assert html =~ "Select a member."
    refute_received {:records, "POST", _path, _body}

    lv |> form("#photo-form", %{member_id: riley.id}) |> render_change()
    assert has_element?(lv, "#photo-lead", "It becomes Riley Okafor's photo")
    # Picking a member keeps the photo already placed.
    assert has_element?(lv, "#photo-placed")

    lv
    |> form("#photo-form", %{member_id: riley.id})
    |> render_submit()
    |> follow_redirect(conn, ~p"/teams/#{team}/members/#{riley.id}/card")

    assert Repo.reload!(riley).has_photo
  end

  test "another team's member cannot be opened or picked", %{conn: conn, team: team} do
    other = member_fixture(team_fixture(%{photos_enabled: true}), %{name: "Other Team"})

    assert_raise Ecto.NoResultsError, fn -> live(conn, add_path(team, other)) end

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos/members/new")
    pick(lv, png_fixture(600, 600))
    html = render_submit(lv, "save", %{"member_id" => to_string(other.id)})

    assert html =~ "Select a member."
    refute Repo.reload!(other).photo_changed_at
    refute_received {:records, _method, _path, _body}
  end

  test "saving with no photo asks for one", %{conn: conn, team: team, riley: riley} do
    {:ok, lv, _html} = live(conn, add_path(team, riley))
    assert render_submit(lv, "save", %{}) =~ "Take a photo, or select one."
  end

  test "a file that is not a photo says so, and the buttons are ready for another", %{
    conn: conn,
    team: team,
    riley: riley
  } do
    {:ok, lv, _html} = live(conn, add_path(team, riley))

    pick(lv, "%PDF-1.7 not a photo")

    assert has_element?(lv, "#flash-error", "Select a photo. SAR Duty cannot read this file.")
    assert has_element?(lv, "#photo-take")
    refute has_element?(lv, "#photo-placed")
    refute has_element?(lv, "#photo-reading")
  end

  test "a refusal names who refused, and the photo stays to send again", %{
    conn: conn,
    team: team,
    riley: riley
  } do
    RecordsStub.stub(fn _method, _path, _body -> {403, %{"title" => "Forbidden"}} end)

    {:ok, lv, _html} = live(conn, add_path(team, riley))
    pick(lv, png_fixture(600, 600))
    html = lv |> form("#photo-form") |> render_submit()

    assert html =~ D4H.error_text(team, %D4H.Error{status: 403, message: "Forbidden (403)"})
    assert has_element?(lv, "#photo-placed")
    refute Repo.reload!(riley).has_photo
    assert [%ChangeSetRow{status: :failed}] = Repo.all(ChangeSetRow)
  end
end
