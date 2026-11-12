defmodule Web.MemberPhotoFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.D4H
  alias App.Model.ChangeSetRow
  alias App.Model.MemberPhoto
  alias App.Model.MemberPhotoFile
  alias App.Model.PhotoAsk
  alias App.Operation.AskForPhoto
  alias App.RecordsStub
  alias App.Repo
  alias Web.PhotoAskLinks

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

  # A member adds their own photo (#1029): it waits for a team admin, and nothing
  # reaches the team's records until one accepts it.
  describe "a member adding their own" do
    setup %{conn: conn} do
      %{team: team, member: cam, user: user} =
        member_with_login_fixture(%{name: "Cameron Ruiz", has_photo: true})

      team =
        team
        |> Ecto.Changeset.change(photos_enabled: true, name: "Coast Range SAR")
        |> Repo.update!()

      %{conn: log_in_user(conn, user), team: team, cam: cam}
    end

    defp add(conn, team, placed \\ %{}) do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos/members/new")
      pick(lv, png_fixture(800, 600))

      lv
      |> form("#photo-form")
      |> render_submit(%{"photo" => placed})
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=yours")
    end

    test "the page is theirs: no Member box, and their own words", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos/members/new")

      refute has_element?(lv, "#photo-member")
      refute has_element?(lv, "#photo-declined")

      assert has_element?(
               lv,
               "#photo-lead",
               "Coast Range SAR puts it on your ID card. A team admin checks it first."
             )

      assert has_element?(lv, ~s|#photo-cancel[href="#{~p"/teams/#{team}/photos?view=yours"}"]|)

      pick(lv, png_fixture(800, 600))
      assert has_element?(lv, "#photo-place-hint", "Move or zoom it so your face fills the oval.")
      assert has_element?(lv, "#photo-save", "Add photo")
    end

    test "it waits with where they placed it, and their ID card keeps the old photo", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      {:ok, lv, html} =
        add(conn, team, %{"turns" => "1", "x" => "0.5", "y" => "0.4", "side" => "0.5"})

      # The toast: its first sentence, then the rest under it.
      assert html =~ "Photo added."
      assert has_element?(lv, "#flash-info", "A team admin checks it.")
      assert has_element?(lv, "#your-photo-status .badge", "Waiting")

      assert [%{status: :waiting} = photo] = Repo.all(MemberPhoto)
      assert {photo.team_id, photo.member_id} == {team.id, cam.id}
      assert {photo.turns, photo.x, photo.y, photo.side} == {1, 0.5, 0.4, 0.5}
      # The photo as taken is kept, with its size, for a team admin to place again.
      assert {photo.width, photo.height} == {800, 600}
      assert photo |> MemberPhotoFile.bytes() |> size() == {800, 600}

      # Nothing went to the team's records: the member's photo is as it was.
      refute_received {:records, _method, _path, _body}
      assert Repo.all(ChangeSetRow) == []
      cam = Repo.reload!(cam)
      assert cam.has_photo
      refute cam.photo_changed_at
    end

    test "a second one replaces the first, file and all", %{conn: conn, team: team} do
      add(conn, team)
      [first] = Repo.all(MemberPhoto)

      add(conn, team, %{"turns" => "2"})

      assert [%{status: :waiting, turns: 2} = second] = Repo.all(MemberPhoto)
      assert second.id != first.id
      assert MemberPhotoFile.bytes(first) == nil
      assert Repo.aggregate(MemberPhotoFile, :count) == 1
    end

    test "a decline of their last photo shows above the examples, with its message", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      member_photo_fixture(cam, %{
        status: :declined,
        decline_reason: :sunglasses,
        decline_message: "Try by the hall's white wall.",
        decided_at: DateTime.utc_now()
      })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos/members/new")

      assert has_element?(lv, "#photo-declined", "Your last photo was declined: Sunglasses.")
      assert has_element?(lv, "#photo-declined-message", "Try by the hall's white wall.")

      # It goes once they add another.
      add(conn, team)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos/members/new")
      refute has_element?(lv, "#photo-declined")
    end

    test "the photo is always of the person logged in, whatever the URL or the form says", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      other = member_fixture(team, %{name: "Sam Rivera"})

      {:ok, lv, _html} = live(conn, add_path(team, other))
      assert has_element?(lv, "#photo-lead", "puts it on your ID card")
      pick(lv, png_fixture(600, 600))
      render_submit(lv, "save", %{"member_id" => to_string(other.id)})

      assert [%{member_id: member_id}] = Repo.all(MemberPhoto)
      assert member_id == cam.id
    end

    # The events a member may send are the page's listed ones (docs/members.md).
    test "the page lists the events a member sends" do
      assert Web.UserAuth.page_access(Web.MemberPhotoFormLive) == :team

      assert Web.UserAuth.view_events(Web.MemberPhotoFormLive) ==
               ["validate", "take-another", "clean-up"]

      assert Web.UserAuth.member_events(Web.MemberPhotoFormLive) == ["save"]
    end
  end

  test "a team admin viewing as a member sees the member's page, and nothing is saved", %{
    conn: conn,
    team: team,
    riley: riley
  } do
    conn = conn |> post(~p"/teams/#{team}/members/#{riley}/view-as") |> recycle()

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos/members/new")
    assert has_element?(lv, "#photo-lead", "A team admin checks it first.")
    pick(lv, png_fixture(600, 600))

    lv |> form("#photo-form") |> render_submit()

    assert has_element?(
             lv,
             "#flash-error",
             "You're viewing as Riley Okafor, so nothing is saved."
           )

    assert Repo.all(MemberPhoto) == []
  end

  test "a team admin's own photo still needs no check", %{conn: conn} do
    %{team: team, member: alex, user: user} =
      member_with_login_fixture(%{name: "Alex Chen", d4h_permission: 0, has_photo: false})

    team =
      team
      |> Ecto.Changeset.change(photos_enabled: true, d4h_access_key: "team-key")
      |> Repo.update!()

    stub_ok()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, add_path(team, alex))
    pick(lv, png_fixture(600, 600))

    lv
    |> form("#photo-form")
    |> render_submit()
    |> follow_redirect(conn, ~p"/teams/#{team}/members/#{alex.id}/card")

    assert Repo.reload!(alex).has_photo
    assert Repo.all(MemberPhoto) == []
  end

  # The link in the email that asks for a photo (#1030): no login, for one member.
  describe "from an ask's link" do
    setup %{team: team, riley: riley} do
      # Member logins are off on this team, and the link works all the same.
      refute team.member_logins
      team = team |> Ecto.Changeset.change(name: "Coast Range SAR") |> Repo.update!()
      asker = App.AccountsFixtures.user_fixture()
      {:ok, [ask]} = AskForPhoto.call(team, asker, riley, nil, DateTime.utc_now())
      %{conn: build_conn(), team: team, ask: ask, link: PhotoAskLinks.path(ask)}
    end

    test "opens Add a photo for the member with no login, and nothing else", %{
      conn: conn,
      link: link
    } do
      {:ok, lv, _html} = live(conn, link)

      assert has_element?(lv, "h1", "Add a photo")
      assert has_element?(lv, "#photo-team", "Coast Range SAR")

      assert has_element?(
               lv,
               "#photo-lead",
               "Coast Range SAR puts it on your ID card. A team admin checks it first."
             )

      assert has_element?(lv, "#photo-take", "Take a photo")
      # No Member box, no trail into the team, and nowhere for Cancel to go.
      refute has_element?(lv, "#photo-member")
      refute has_element?(lv, ".breadcrumbs")
      refute has_element?(lv, "#photo-cancel")
    end

    test "the photo waits for a team admin, is that member's whatever the form says, and the ask closes",
         %{conn: conn, team: team, riley: riley, ask: ask, link: link} do
      other = member_fixture(team, %{has_photo: false})
      {:ok, lv, _html} = live(conn, link)
      pick(lv, png_fixture(800, 600))
      assert has_element?(lv, "#photo-save", "Add photo")

      html =
        lv
        |> form("#photo-form")
        |> render_submit(%{"member_id" => to_string(other.id), "photo" => %{"turns" => "1"}})

      assert html =~ "Photo added"
      assert has_element?(lv, "#photo-link-done", "A team admin checks it")
      refute has_element?(lv, "#photo-form")

      assert [%MemberPhoto{status: :waiting, turns: 1} = waiting] = Repo.all(MemberPhoto)
      assert waiting.member_id == riley.id
      assert Repo.get_by(MemberPhotoFile, member_photo_id: waiting.id)
      refute Repo.reload!(riley).has_photo
      assert Repo.reload!(ask).closed_at

      # The ask closed, so the link stops.
      {:ok, lv, _html} = live(conn, link)
      assert has_element?(lv, "h1", "This link no longer works")
      assert has_element?(lv, "#photo-link-ended", "Ask a team admin for a new one.")
      refute has_element?(lv, "#photo-form")
    end

    test "a team admin adding the photo closes the ask, and the link stops", %{
      conn: conn,
      team: team,
      riley: riley,
      ask: ask,
      link: link
    } do
      stub_ok()
      %{user: admin} = user_with_team_fixture()
      manager_fixture(team, %{email: admin.email})
      admin_conn = log_in_user(build_conn(), admin)

      {:ok, lv, _html} = live(admin_conn, add_path(team, riley))
      pick(lv, png_fixture(600, 600))

      lv
      |> form("#photo-form")
      |> render_submit()
      |> follow_redirect(admin_conn, ~p"/teams/#{team}/members/#{riley.id}/card")

      assert Repo.reload!(ask).closed_at
      {:ok, lv, _html} = live(conn, link)
      assert has_element?(lv, "h1", "This link no longer works")
    end

    test "an ask that closes while the page is open saves nothing", %{
      conn: conn,
      riley: riley,
      link: link
    } do
      {:ok, lv, _html} = live(conn, link)
      pick(lv, png_fixture(800, 600))
      PhotoAsk.close_for_member(riley, DateTime.utc_now())

      html = lv |> form("#photo-form") |> render_submit()

      assert html =~ "This link no longer works"
      assert Repo.all(MemberPhoto) == []
    end

    test "a link over 30 days old no longer works, and one that was never a link is not found",
         %{conn: conn, ask: ask} do
      old =
        Phoenix.Token.sign(Web.Endpoint, "photo ask", ask.id,
          signed_at: System.system_time(:second) - 31 * 24 * 60 * 60
        )

      {:ok, lv, _html} = live(conn, ~p"/photos/#{old}")
      assert has_element?(lv, "h1", "This link no longer works")

      assert_error_sent 404, fn -> live(conn, ~p"/photos/not-a-token") end
    end

    test "with Photos off the link no longer works", %{conn: conn, team: team, link: link} do
      team |> Ecto.Changeset.change(photos_enabled: false) |> Repo.update!()
      {:ok, lv, _html} = live(conn, link)
      assert has_element?(lv, "h1", "This link no longer works")
    end
  end

  # Clean up (#1031) is off unless a test turns its stand-in on, as production is until
  # the function exists.
  test "with Clean up off nothing mentions it, and nothing is asked of it", %{
    conn: conn,
    team: team,
    riley: riley
  } do
    {:ok, lv, _html} = live(conn, add_path(team, riley))

    # The guide is part 1's: the first test checks its rules and examples.
    assert has_element?(lv, "#photo-guide-good li", "A plain, light wall behind you")
    refute has_element?(lv, "#photo-clean-up-line")

    pick(lv, png_fixture(800, 600))

    # Placed as taken at once: no wait, no switch, no warning, and no toast, which a
    # call to Clean up while it is off would have left.
    assert has_element?(lv, ~s|#photo-placed .photo-place img[width="800"][height="600"]|)
    assert has_element?(lv, "#photo-place-hint", "Move or zoom it so the face fills the oval.")
    refute has_element?(lv, "#photo-cleaning")
    refute has_element?(lv, "#photo-clean-up")
    refute has_element?(lv, ".warning-text")
    refute has_element?(lv, "#flash-error")
    refute render(lv) =~ "Clean up"
  end

  describe "with Clean up available" do
    alias App.CleanUpStandIn

    # The buttons under the photo, in order: `{id, leads?}`.
    defp buttons(lv) do
      lv
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("#photo-placed .form-actions .btn")
      |> Enum.map(fn button ->
        [id] = Floki.attribute(button, "id")
        [class] = Floki.attribute(button, "class")
        {id, class =~ "btn-success"}
      end)
    end

    defp pick_and_clean_up(lv, bytes \\ png_fixture(800, 600)) do
      pick(lv, bytes)
      render_async(lv)
    end

    defp records_team(conn) do
      %{user: user, team: team} =
        records_team_with_user_fixture(%{d4h_access_key: "sdr_key", photos_enabled: true})

      member = member_fixture(team, %{name: "Casey New", has_photo: false})
      stub_ok()
      %{conn: log_in_user(conn, user), team: team, member: member}
    end

    test "the guide takes any background, and says what Clean up does", %{
      conn: conn,
      team: team,
      riley: riley
    } do
      CleanUpStandIn.turn_on()
      {:ok, lv, _html} = live(conn, add_path(team, riley))

      rules = lv |> render() |> Floki.parse_fragment!() |> Floki.find("#photo-guide-good li")
      assert length(rules) == 4
      assert has_element?(lv, "#photo-guide-good li", "Any background. SAR Duty removes it.")
      refute has_element?(lv, "#photo-guide-good li", "A plain, light wall behind you")

      bad = lv |> render() |> Floki.parse_fragment!() |> Floki.find("#photo-guide-bad > li")
      assert length(bad) == 4
      refute has_element?(lv, "#photo-guide-bad li", "Busy background")

      assert has_element?(
               lv,
               "#photo-clean-up-line",
               "SAR Duty cleans it up: it removes the background and centres the face. You see the result before you save it."
             )
    end

    test "the page says Cleaning up… while it waits", %{conn: conn, team: team, riley: riley} do
      test = self()

      CleanUpStandIn.turn_on(
        answer: fn _jpeg, :member ->
          send(test, {:cleaning_up, self()})

          receive do
            :answer -> CleanUpStandIn.found(1)
          end
        end
      )

      {:ok, lv, _html} = live(conn, add_path(team, riley))
      pick(lv, png_fixture(800, 600))

      assert_receive {:cleaning_up, clean_up}
      assert has_element?(lv, "#photo-cleaning", "Cleaning up…")
      refute has_element?(lv, "#photo-pick")
      refute has_element?(lv, "#photo-placed")

      send(clean_up, :answer)
      render_async(lv)

      refute has_element?(lv, "#photo-cleaning")
      assert has_element?(lv, "#photo-placed")
    end

    test "the result arrives placed, with the switch on, and off shows the photo as taken", %{
      conn: conn,
      team: team,
      riley: riley
    } do
      CleanUpStandIn.turn_on()
      {:ok, lv, _html} = live(conn, add_path(team, riley))
      pick_and_clean_up(lv)

      # The stand-in's centred square of an 800 × 600 photo, whole in the square.
      assert has_element?(lv, ~s|#photo-placed .photo-place img[width="600"][height="600"]|)
      assert has_element?(lv, ~s|#photo-placed input[name="photo[side]"][value="1.0"]|)
      assert has_element?(lv, "#photo-clean-up[role=switch][checked]")
      assert has_element?(lv, "label[for=photo-clean-up]", "Clean up")

      assert has_element?(
               lv,
               "#photo-clean-up-hint",
               "Removes the background and centres the face. Turn it off to use the photo as it is."
             )

      assert has_element?(
               lv,
               "#photo-place-hint",
               "Cleaned up. Move or zoom it if the face is not in the oval."
             )

      for tool <- ~w(rotate zoom-out zoom-in), do: assert(has_element?(lv, "#photo-#{tool}"))
      refute has_element?(lv, ".warning-text")

      assert buttons(lv) == [
               {"photo-save", true},
               {"photo-another", false},
               {"photo-cancel", false}
             ]

      lv |> element("#photo-clean-up") |> render_click()

      assert has_element?(lv, ~s|#photo-placed .photo-place img[width="800"][height="600"]|)
      refute has_element?(lv, "#photo-clean-up[checked]")
      assert has_element?(lv, "#photo-place-hint", "Move or zoom it so the face fills the oval.")

      lv |> element("#photo-clean-up") |> render_click()
      assert has_element?(lv, ~s|#photo-placed .photo-place img[width="600"][height="600"]|)

      # Take another starts again from the guide.
      lv |> element("#photo-another") |> render_click()
      assert has_element?(lv, "#photo-pick")
      refute has_element?(lv, "#photo-clean-up")
    end

    test "a face off the oval starts the square on it", %{conn: conn, team: team, riley: riley} do
      face = %{x: 0.3, y: 0.3, width: 0.1, height: 0.208}
      CleanUpStandIn.turn_on(answer: fn _jpeg, :member -> CleanUpStandIn.found(1, face) end)

      {:ok, lv, _html} = live(conn, add_path(team, riley))
      pick_and_clean_up(lv)

      assert has_element?(lv, ~s|#photo-placed input[name="photo[x]"][value="0.3"]|)
      assert has_element?(lv, ~s|#photo-placed input[name="photo[side]"][value^="0.4"]|)
    end

    test "Save photo sends what the switch shows", %{conn: conn} do
      # A 300 × 300 cleaned-up photo of one 800 × 600 as taken: the size says which went.
      CleanUpStandIn.turn_on(answer: fn _jpeg, :member -> CleanUpStandIn.found(1) end)
      %{conn: conn, team: team, member: member} = records_team(conn)
      path = "/members/#{member.d4h_member_id}/image"

      {:ok, lv, _html} = live(conn, add_path(team, member))
      pick_and_clean_up(lv)
      lv |> form("#photo-form") |> render_submit()

      assert_received {:records, "PUT", ^path, {:bytes, cleaned}}
      assert size(cleaned) == {300, 300}

      {:ok, lv, _html} = live(conn, add_path(team, member))
      pick_and_clean_up(lv)
      lv |> element("#photo-clean-up") |> render_click()
      lv |> form("#photo-form") |> render_submit()

      assert_received {:records, "PUT", ^path, {:bytes, taken}}
      assert size(taken) == {600, 600}
      # A team admin's photo does not wait, so nothing is kept.
      assert Repo.all(MemberPhoto) == []
    end

    test "more than 1 face warns, Take another leads, and Save photo still works", %{conn: conn} do
      CleanUpStandIn.turn_on(answer: fn _jpeg, :member -> CleanUpStandIn.found(2) end)
      %{conn: conn, team: team, member: member} = records_team(conn)

      {:ok, lv, _html} = live(conn, add_path(team, member))
      pick_and_clean_up(lv)

      assert has_element?(
               lv,
               "#photo-warning-faces.warning-text",
               "2 faces in this photo. Take one with only the member in it."
             )

      assert buttons(lv) == [
               {"photo-another", true},
               {"photo-save", false},
               {"photo-cancel", false}
             ]

      assert has_element?(lv, "#photo-another", "Take another")
      assert has_element?(lv, "#photo-save", "Save photo")
      assert has_element?(lv, "#photo-clean-up[checked]")

      lv
      |> form("#photo-form")
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      assert Repo.reload!(member).has_photo
    end

    test "no face warns, and the photo starts on the middle square", %{
      conn: conn,
      team: team,
      riley: riley
    } do
      CleanUpStandIn.turn_on(answer: fn _jpeg, :member -> CleanUpStandIn.found(0) end)
      {:ok, lv, _html} = live(conn, add_path(team, riley))
      pick_and_clean_up(lv)

      assert has_element?(
               lv,
               "#photo-warning-no-face",
               "No face found in this photo. Take another, or place it yourself."
             )

      assert has_element?(lv, ~s|#photo-placed input[name="photo[side]"][value="1.0"]|)
      assert [{"photo-another", true}, {"photo-save", false} | _cancel] = buttons(lv)
    end

    test "a dark photo warns, after what the faces say", %{conn: conn, team: team, riley: riley} do
      CleanUpStandIn.turn_on(answer: fn _jpeg, :member -> CleanUpStandIn.found(3) end)
      dark = 800 |> Image.new!(600, color: [12, 12, 12]) |> Image.write!(:memory, suffix: ".png")

      {:ok, lv, _html} = live(conn, add_path(team, riley))
      pick_and_clean_up(lv, dark)

      warnings = lv |> render() |> Floki.parse_fragment!() |> Floki.find(".warning-text")

      assert Enum.flat_map(warnings, &Floki.attribute(&1, "id")) ==
               ["photo-warning-faces", "photo-warning-dark"]

      assert has_element?(lv, "#photo-warning-faces", "3 faces in this photo.")

      assert has_element?(
               lv,
               "#photo-warning-dark",
               "This photo is dark. Take another in daylight or a bright room."
             )

      # The warnings are about the photo, so they stay with the switch off.
      lv |> element("#photo-clean-up") |> render_click()
      assert has_element?(lv, "#photo-warning-dark")
    end

    test "an error gives the toast, and the photo is placed as taken", %{
      conn: conn,
      team: team,
      riley: riley
    } do
      stub_ok()
      CleanUpStandIn.turn_on(answer: fn _jpeg, :member -> {:error, :unreachable} end)
      {:ok, lv, _html} = live(conn, add_path(team, riley))
      pick_and_clean_up(lv)

      assert has_element?(lv, "#flash-error", "Clean up did not answer.")
      assert has_element?(lv, "#flash-error", "Place the photo yourself.")
      assert has_element?(lv, ~s|#photo-placed .photo-place img[width="800"][height="600"]|)
      assert has_element?(lv, "#photo-place-hint", "Move or zoom it so the face fills the oval.")
      refute has_element?(lv, "#photo-clean-up")
      refute has_element?(lv, ".warning-text")
      assert [{"photo-save", true}, {"photo-another", false} | _cancel] = buttons(lv)

      lv
      |> form("#photo-form")
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/members/#{riley.id}/card")

      assert Repo.reload!(riley).has_photo
    end

    test "a timeout gives the same toast", %{conn: conn, team: team, riley: riley} do
      CleanUpStandIn.turn_on(
        timeout: 20,
        answer: fn _jpeg, :member ->
          Process.sleep(5_000)
          CleanUpStandIn.found(1)
        end
      )

      {:ok, lv, _html} = live(conn, add_path(team, riley))
      pick_and_clean_up(lv)

      assert has_element?(lv, "#flash-error", "Clean up did not answer.")
      assert has_element?(lv, ~s|#photo-placed .photo-place img[width="800"][height="600"]|)
      refute has_element?(lv, "#photo-clean-up")
    end

    test "a cleaned-up photo that cannot be read gives the toast too", %{
      conn: conn,
      team: team,
      riley: riley
    } do
      CleanUpStandIn.turn_on(
        answer: fn _jpeg, :member -> {:ok, %{bytes: "not a photo", faces: 1, face: nil}} end
      )

      {:ok, lv, _html} = live(conn, add_path(team, riley))
      pick_and_clean_up(lv)

      assert has_element?(lv, "#flash-error", "Clean up did not answer.")
      refute has_element?(lv, "#photo-clean-up")
    end
  end

  describe "a member adding their own, with Clean up available" do
    alias App.CleanUpStandIn

    setup %{conn: conn} do
      %{team: team, member: cam, user: user} =
        member_with_login_fixture(%{name: "Cameron Ruiz", has_photo: true})

      team = team |> Ecto.Changeset.change(photos_enabled: true) |> Repo.update!()
      %{conn: log_in_user(conn, user), team: team, cam: cam}
    end

    defp open_and_pick(conn, team) do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos/members/new")
      pick(lv, png_fixture(800, 600))
      render_async(lv)
      lv
    end

    test "the words are theirs", %{conn: conn, team: team} do
      CleanUpStandIn.turn_on(answer: fn _jpeg, :member -> CleanUpStandIn.found(2) end)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/photos/members/new")

      assert has_element?(
               lv,
               "#photo-clean-up-line",
               "SAR Duty cleans it up: it removes the background and centres your face. You see the result before anyone else does."
             )

      pick(lv, png_fixture(800, 600))
      render_async(lv)

      assert has_element?(
               lv,
               "#photo-place-hint",
               "Cleaned up. Move or zoom it if your face is not in the oval."
             )

      assert has_element?(
               lv,
               "#photo-clean-up-hint",
               "Removes the background and centres your face. Turn it off to use your photo as it is."
             )

      assert has_element?(
               lv,
               "#photo-warning-faces",
               "2 faces in this photo. Take one with only you in it."
             )

      assert has_element?(lv, "#photo-another.btn-success", "Take another")
      assert has_element?(lv, "#photo-save", "Add photo")
    end

    test "the waiting photo keeps both, and that the switch was on", %{
      conn: conn,
      team: team,
      cam: cam
    } do
      CleanUpStandIn.turn_on()
      lv = open_and_pick(conn, team)

      lv
      |> form("#photo-form")
      |> render_submit(%{
        "photo" => %{"turns" => "0", "x" => "0.5", "y" => "0.4", "side" => "0.5"}
      })
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=yours")

      assert [%{status: :waiting, clean_up: true} = photo] = Repo.all(MemberPhoto)
      assert photo.member_id == cam.id
      assert {photo.width, photo.height} == {800, 600}
      assert {photo.cleaned_width, photo.cleaned_height} == {600, 600}
      assert {photo.x, photo.y, photo.side} == {0.5, 0.4, 0.5}
      assert photo |> MemberPhotoFile.bytes(:taken) |> size() == {800, 600}
      assert photo |> MemberPhotoFile.bytes(:cleaned) |> size() == {600, 600}

      # Photos shows the square they placed, cut from the cleaned-up photo.
      placed = get(conn, ~p"/teams/#{team}/photos/members/#{photo.id}/file?shape=placed")
      assert placed |> response(200) |> size() == {300, 300}
      cleaned = get(conn, ~p"/teams/#{team}/photos/members/#{photo.id}/file?shape=cleaned")
      assert cleaned |> response(200) |> size() == {600, 600}
    end

    test "with the switch off it keeps both all the same, and that it was off", %{
      conn: conn,
      team: team
    } do
      CleanUpStandIn.turn_on()
      lv = open_and_pick(conn, team)
      lv |> element("#photo-clean-up") |> render_click()

      lv
      |> form("#photo-form")
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=yours")

      assert [%{status: :waiting, clean_up: false} = photo] = Repo.all(MemberPhoto)
      assert {photo.cleaned_width, photo.cleaned_height} == {600, 600}
      assert photo |> MemberPhotoFile.bytes(:cleaned) |> size() == {600, 600}

      # The square is cut from the photo as taken: its whole shorter side.
      placed = get(conn, ~p"/teams/#{team}/photos/members/#{photo.id}/file?shape=placed")
      assert placed |> response(200) |> size() == {600, 600}
    end

    test "a warning does not stop Add photo", %{conn: conn, team: team} do
      CleanUpStandIn.turn_on(answer: fn _jpeg, :member -> CleanUpStandIn.found(0) end)
      lv = open_and_pick(conn, team)
      assert has_element?(lv, "#photo-warning-no-face")

      lv
      |> form("#photo-form")
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=yours")

      assert [%{status: :waiting, clean_up: true}] = Repo.all(MemberPhoto)
    end

    test "when Clean up does not answer, the photo waits as taken, with no cleaned-up copy", %{
      conn: conn,
      team: team
    } do
      CleanUpStandIn.turn_on(answer: fn _jpeg, :member -> {:error, :unreachable} end)
      lv = open_and_pick(conn, team)

      assert has_element?(lv, "#flash-error", "Place your photo yourself.")

      lv
      |> form("#photo-form")
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/photos?view=yours")

      assert [%{status: :waiting, clean_up: false, cleaned_width: nil} = photo] =
               Repo.all(MemberPhoto)

      assert MemberPhotoFile.bytes(photo, :cleaned) == nil
      assert is_binary(MemberPhotoFile.bytes(photo, :taken))
    end
  end
end
