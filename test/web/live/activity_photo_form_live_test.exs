defmodule Web.ActivityPhotoFormLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ActivityPhoto
  alias App.Repo

  # Add photos (#1032): a member who attended an exercise or an event adds their photos
  # of it, with a caption and permission to post for the send.
  setup %{conn: conn} do
    team = member_logins_team_fixture(%{name: "Coast Range SAR", photos_enabled: true})
    cam = member_fixture(team, %{name: "Cameron Ruiz", d4h_permission: 2})
    user = user_fixture(%{email: cam.email})

    activity =
      activity_fixture(team, %{
        title: "Swiftwater training",
        ref_id: "01470",
        started_at: ~U[2026-11-04 03:00:00Z],
        finished_at: ~U[2026-11-04 05:30:00Z]
      })

    attendance_fixture(activity, cam)
    %{conn: log_in_user(conn, user), team: team, cam: cam, user: user, activity: activity}
  end

  defp add(team, activity), do: ~p"/teams/#{team}/activities/#{activity.id}/photos/new"
  defp tab(team, activity), do: ~p"/teams/#{team}/activities/#{activity.id}/photos"

  # How long a test waits for the photos to be read, in ms, before the page moves on.
  @wait 5_000

  defp entry(name, bytes \\ nil),
    do: %{name: name, content: bytes || png_fixture(90, 60), type: "image/png"}

  # Picks the files, which upload at once.
  defp pick(lv, entries) do
    input = file_input(lv, "#photos-form", :photos, entries)
    for %{name: name} <- entries, do: render_upload(input, name)
    input
  end

  defp count(lv, selector),
    do: lv |> render() |> Floki.parse_fragment!() |> Floki.find(selector) |> length()

  # The error toast's words: its first sentence is its title, and the rest sits under it.
  defp toast(lv) do
    lv
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("#flash-error .toast-title, #flash-error .toast-sub")
    |> Enum.map_join(" ", &Floki.text/1)
  end

  test "opens with the rules above the files, every time", %{
    conn: conn,
    team: team,
    activity: activity
  } do
    {:ok, lv, _html} = live(conn, add(team, activity))

    assert page_title(lv) =~ "Swiftwater training · Add photos"
    assert has_element?(lv, ~s|.breadcrumbs a[href="#{tab(team, activity)}"]|, "Photos")
    assert has_element?(lv, "h1", "Add photos")

    # The activity's day on the team's clock: Nov 3 in Vancouver, Nov 4 in UTC.
    assert has_element?(
             lv,
             "#photos-lead",
             "From Swiftwater training, Nov 3, 2026. A team admin looks at them before the team sees them."
           )

    assert has_element?(lv, "h2", "Before you add")
    assert count(lv, "#photos-rules > li") == 4

    assert has_element?(
             lv,
             "#photos-rules li",
             "Exercises and events only. Never from an incident."
           )

    assert has_element?(lv, "#photos-rules li", "No one from the public unless they said yes.")

    assert has_element?(
             lv,
             "#photos-rules li",
             "No licence plates, house numbers, or maps of a search."
           )

    assert has_element?(lv, "#photos-rules li", "Ask a member before you add a close-up of them.")

    assert has_element?(lv, "#photos-label", "Photos")
    assert has_element?(lv, "#photos-pick", "Up to 20 at a time, 25 MB each.")
    # Take a photo asks for the camera on the back of the phone; Select photos takes many.
    assert has_element?(
             lv,
             "#photos-take[data-photo-pick=camera][data-photo-capture=environment]",
             "Take a photo"
           )

    assert has_element?(lv, "#photos-select[data-photo-pick=file]", "Select photos")
    assert has_element?(lv, ~s|#photos-pick input[type=file][accept="image/*"][multiple]|)

    assert has_element?(lv, ~s|label[for="photos-caption"]|, "Caption (optional)")
    assert has_element?(lv, "#photos-form", "What is happening. The team may use it in a post.")
    assert has_element?(lv, ~s|#photos-caption[maxlength="300"]|)

    # Permission to post starts unchecked.
    refute has_element?(lv, "#photos-may-post[checked]")

    assert has_element?(
             lv,
             ~s|label[for="photos-may-post"]|,
             "Coast Range SAR may post these on its website and social media."
           )

    assert has_element?(
             lv,
             "#photos-form",
             "You keep them. Ask a team admin to take one down at any time."
           )

    assert has_element?(lv, "#photos-save", "Add photos")
    assert has_element?(lv, ~s|#photos-cancel[href="#{tab(team, activity)}"]|, "Cancel")
    # Photos only: no video.
    refute render(lv) =~ ~r/video/i
  end

  test "lists each photo picked with Remove, and the button counts them", %{
    conn: conn,
    team: team,
    activity: activity
  } do
    {:ok, lv, _html} = live(conn, add(team, activity))
    pick(lv, [entry("river.png"), entry("throw.png"), entry("cliff.png")])

    assert count(lv, "#photos-picked > li") == 3
    assert has_element?(lv, "#photos-picked li", "river.png")
    assert has_element?(lv, "#photos-save", "Add 3 photos")

    lv |> element("#photos-picked li:nth-child(2) a", "Remove") |> render_click()

    assert count(lv, "#photos-picked > li") == 2
    refute has_element?(lv, "#photos-picked li", "throw.png")
    assert has_element?(lv, "#photos-save", "Add 2 photos")

    lv |> element("#photos-picked li:nth-child(1) a", "Remove") |> render_click()
    assert has_element?(lv, "#photos-save", "Add 1 photo")
  end

  test "Add keeps the photos waiting, with the caption, and lands on the Photos tab", ctx do
    %{conn: conn, team: team, activity: activity, cam: cam, user: user} = ctx
    {:ok, lv, _html} = live(conn, add(team, activity))
    pick(lv, [entry("river.png"), entry("throw.png", located_jpeg_fixture(800, 600))])

    # The photos are read beside the page, which says so until they are in.
    adding =
      lv
      |> form("#photos-form", %{
        "caption" => "Throw bag practice at Cedar Creek.",
        "may_post" => "true"
      })
      |> render_submit()

    assert adding =~ "Adding 2 photos…"
    assert adding |> Floki.parse_fragment!() |> Floki.find("#photos-save[disabled]") != []

    {path, flash} = assert_redirect(lv, @wait)
    assert path == tab(team, activity)
    assert flash["info"] == "2 photos added. A team admin checks them."

    # The plain one, 90 wide, then the one that said where it was taken, 800 wide.
    assert [first, second] = ActivityPhoto |> Repo.all() |> Enum.sort_by(& &1.width)

    for photo <- [first, second] do
      assert photo.status == :waiting
      assert photo.activity_id == activity.id
      assert photo.member_id == cam.id
      assert photo.added_by_user_id == user.id
      assert photo.caption == "Throw bag practice at Cedar Creek."
      assert photo.may_post
    end

    # Where it was taken, and with what, is gone from every file kept.
    assert {second.width, second.height} == {800, 600}

    assert [{:ok, _original}, {:ok, _show}, {:ok, _tile}] = activity_photo_files(second)
    for {:ok, bytes} <- activity_photo_files(second), do: refute(bytes =~ "Exif")

    # The member sees their own on the tab, marked Waiting.
    {:ok, lv, _html} = live(conn, path)
    assert has_element?(lv, "#photo-#{first.id}-waiting", "Waiting")
  end

  test "an unchecked permission box is kept as no", %{conn: conn, team: team, activity: activity} do
    {:ok, lv, _html} = live(conn, add(team, activity))
    pick(lv, [entry("river.png")])

    lv |> form("#photos-form", %{"caption" => ""}) |> render_submit()

    {_path, flash} = assert_redirect(lv, @wait)
    assert flash["info"] == "1 photo added. A team admin checks it."
    assert %ActivityPhoto{may_post: false, caption: nil} = Repo.one!(ActivityPhoto)
  end

  test "with no photo picked, Add says what to do", %{conn: conn, team: team, activity: activity} do
    {:ok, lv, _html} = live(conn, add(team, activity))

    assert lv |> form("#photos-form") |> render_submit() =~ "Take a photo, or select some."
    assert Repo.all(ActivityPhoto) == []
  end

  test "a file SAR Duty cannot read is refused when it arrives, by name", %{
    conn: conn,
    team: team,
    activity: activity
  } do
    {:ok, lv, _html} = live(conn, add(team, activity))

    pick(lv, [
      entry("river.png"),
      %{name: "notes.png", content: "%PDF-1.7 notes", type: "image/png"}
    ])

    assert toast(lv) == "notes.png: Select photos. SAR Duty cannot read this file."
    assert count(lv, "#photos-picked > li") == 1
    assert has_element?(lv, "#photos-save", "Add 1 photo")
  end

  test "a photo over 25 MB is refused, by name", %{conn: conn, team: team, activity: activity} do
    {:ok, lv, _html} = live(conn, add(team, activity))

    # Its size is all the page reads: a file this large never uploads.
    huge = :binary.copy(<<0>>, 25_000_001)
    input = file_input(lv, "#photos-form", :photos, [entry("huge.png", huge)])

    preflight_upload(input)
    render_change(form(lv, "#photos-form"))

    assert toast(lv) == "huge.png: That file is too large. Use one under 25 MB."
    refute has_element?(lv, "#photos-picked")
  end

  test "takes 20 photos a send, and leaves out the rest", %{
    conn: conn,
    team: team,
    activity: activity
  } do
    {:ok, lv, _html} = live(conn, add(team, activity))
    bytes = png_fixture(30, 20)
    pick(lv, for(n <- 1..20, do: entry("photo-#{n}.png", bytes)))
    assert has_element?(lv, "#photos-save", "Add 20 photos")

    input = file_input(lv, "#photos-form", :photos, [entry("photo-21.png", bytes)])
    preflight_upload(input)
    render_change(form(lv, "#photos-form"))

    assert toast(lv) == "Add up to 20 photos at a time. The rest were left out."
    assert count(lv, "#photos-picked > li") == 20
    refute has_element?(lv, "#photos-picked li", "photo-21.png")

    lv |> form("#photos-form") |> render_submit()
    assert_redirect(lv, @wait)
    assert Repo.aggregate(ActivityPhoto, :count) == 20
  end

  test "a caption over 300 characters is refused", %{conn: conn, team: team, activity: activity} do
    {:ok, lv, _html} = live(conn, add(team, activity))
    pick(lv, [entry("river.png")])

    assert lv
           |> form("#photos-form", %{"caption" => String.duplicate("a", 301)})
           |> render_submit() =~ "Keep the caption under 300 characters."

    assert Repo.all(ActivityPhoto) == []
    # The photo is still there to send.
    assert has_element?(lv, "#photos-save", "Add 1 photo")
  end

  test "is not found for a member who did not attend, an incident, or an activity still to start",
       ctx do
    %{conn: conn, team: team, activity: activity, cam: cam} = ctx

    absent = member_fixture(team, %{d4h_permission: 2})
    other = log_in_user(build_conn(), user_fixture(%{email: absent.email}))
    assert_error_sent 404, fn -> get(other, add(team, activity)) end

    incident = activity_fixture(team, %{activity_kind: "incident"})
    attendance_fixture(incident, cam)
    assert_error_sent 404, fn -> get(conn, add(team, incident)) end

    coming = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), 1, :day)})
    attendance_fixture(coming, cam)
    assert_error_sent 404, fn -> get(conn, add(team, coming)) end
  end

  test "a team admin adds to an activity they did not attend, and theirs wait too", ctx do
    %{team: team, activity: activity} = ctx
    admin = user_fixture()
    alex = manager_fixture(team, %{email: admin.email, name: "Alex Chen"})
    conn = log_in_user(build_conn(), admin)

    {:ok, lv, _html} = live(conn, add(team, activity))
    pick(lv, [entry("river.png")])
    lv |> form("#photos-form") |> render_submit()
    assert_redirect(lv, @wait)

    # Under their own member row, found by email.
    assert %ActivityPhoto{status: :waiting, member_id: member_id} = Repo.one!(ActivityPhoto)
    assert member_id == alex.id
  end

  test "a team admin viewing as a member picks, and saves nothing", ctx do
    %{team: team, activity: activity, cam: cam} = ctx
    admin = user_fixture()
    manager_fixture(team, %{email: admin.email})

    conn =
      build_conn() |> log_in_user(admin) |> post(~p"/teams/#{team}/members/#{cam.id}/view-as")

    {:ok, lv, _html} = live(conn, add(team, activity))
    pick(lv, [entry("river.png")])

    assert lv |> form("#photos-form") |> render_submit() =~
             "viewing as Cameron Ruiz, so nothing is saved"

    assert Repo.all(ActivityPhoto) == []
  end
end
