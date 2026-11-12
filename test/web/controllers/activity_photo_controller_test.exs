defmodule Web.ActivityPhotoControllerTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Repo

  # An activity photo's file (#1032): an accepted one is anyone's on the team, and a
  # waiting one a team admin's or the member's who added it. Nobody else gets it.
  setup %{conn: conn} do
    team = member_logins_team_fixture(%{photos_enabled: true})
    admin = user_fixture()
    manager_fixture(team, %{email: admin.email})
    cam = member_fixture(team, %{name: "Cameron Ruiz", d4h_permission: 2})
    noor = member_fixture(team, %{name: "Noor Aziz", d4h_permission: 2})
    activity = activity_fixture(team)

    %{
      conn: conn,
      team: team,
      admin: admin,
      cam: cam,
      noor: noor,
      activity: activity,
      waiting: activity_photo_fixture(activity, %{member_id: cam.id}),
      accepted: activity_photo_fixture(activity, %{member_id: cam.id, status: :accepted})
    }
  end

  defp as(conn, %{email: email}), do: log_in_user(conn, user_fixture(%{email: email}))
  defp file(team, photo, query \\ []), do: ~p"/teams/#{team}/photos/#{photo.id}/file?#{query}"

  defp size(conn) do
    image = Image.from_binary!(conn.resp_body)
    {Image.width(image), Image.height(image)}
  end

  test "an accepted photo is anyone's on the team, in three sizes", ctx do
    %{conn: conn, team: team, accepted: photo, noor: noor} = ctx
    conn = as(conn, noor)

    for size <- ~w(tile show original) do
      got = get(conn, file(team, photo, size: size))
      assert got.status == 200
      assert get_resp_header(got, "content-type") == ["image/jpeg"]
      assert get_resp_header(got, "x-content-type-options") == ["nosniff"]
      # A browser keeps it a day; nothing shared does.
      assert get_resp_header(got, "cache-control") == ["private, max-age=86400, immutable"]
      assert size(got) == {60, 40}
    end

    # With no size, the copy to show. A size that is not one is not found.
    assert get(conn, file(team, photo)).status == 200
    assert_error_sent 404, fn -> get(conn, file(team, photo, size: "huge")) end
  end

  test "a waiting photo is a team admin's and the member's who added it", ctx do
    %{conn: conn, team: team, waiting: photo, admin: admin, cam: cam} = ctx

    for conn <- [log_in_user(conn, admin), as(conn, cam)], size <- ~w(tile show original) do
      got = get(conn, file(team, photo, size: size))
      assert got.status == 200
      # It can be deleted at any time, so nothing keeps it.
      assert get_resp_header(got, "cache-control") == ["private, no-store"]
    end
  end

  test "another member's waiting photo is not found, in any size", ctx do
    %{conn: conn, team: team, waiting: photo, noor: noor} = ctx
    conn = as(conn, noor)

    for size <- ~w(tile show original),
        do: assert_error_sent(404, fn -> get(conn, file(team, photo, size: size)) end)

    assert_error_sent 404, fn -> get(conn, file(team, photo)) end
  end

  test "a team admin viewing as another member does not get it either", ctx do
    %{conn: conn, team: team, waiting: photo, admin: admin, cam: cam, noor: noor} = ctx
    conn = log_in_user(conn, admin)

    as_noor = post(conn, ~p"/teams/#{team}/members/#{noor.id}/view-as")
    assert_error_sent 404, fn -> get(recycle(as_noor), file(team, photo)) end

    # Viewing as the member who added it, they get what the member gets.
    as_cam = post(conn, ~p"/teams/#{team}/members/#{cam.id}/view-as")
    assert get(recycle(as_cam), file(team, photo)).status == 200
  end

  test "nobody on another team gets a photo, waiting or accepted", ctx do
    %{conn: conn, team: team, waiting: waiting, accepted: accepted} = ctx
    %{user: outsider, team: other} = user_with_team_fixture(%{team: %{photos_enabled: true}})
    conn = log_in_user(conn, outsider)

    for photo <- [waiting, accepted] do
      # Their own team's URL finds none of this team's photos.
      assert_error_sent 404, fn -> get(conn, file(other, photo)) end
      # And this team's URL is not theirs to open.
      assert_error_sent 404, fn -> get(conn, file(team, photo)) end
    end
  end

  test "nobody logged out gets a photo", ctx do
    %{conn: conn, team: team, accepted: accepted} = ctx
    assert redirected_to(get(conn, file(team, accepted))) =~ "/login"
  end

  test "a member never gets a deleted activity's photo; a team admin does", ctx do
    %{conn: conn, team: team, accepted: photo, admin: admin, cam: cam, activity: activity} = ctx
    activity |> Ecto.Changeset.change(deleted_at: ~U[2026-11-04 18:00:00Z]) |> Repo.update!()

    assert_error_sent 404, fn -> conn |> as(cam) |> get(file(team, photo)) end
    assert conn |> log_in_user(admin) |> get(file(team, photo)) |> Map.fetch!(:status) == 200
  end

  test "with Photos off, no file is served", ctx do
    %{conn: conn, team: team, accepted: photo, admin: admin} = ctx
    team |> Ecto.Changeset.change(photos_enabled: false) |> Repo.update!()

    assert_error_sent 404, fn -> conn |> log_in_user(admin) |> get(file(team, photo)) end
  end

  test "an id that is not a number is not found", ctx do
    %{conn: conn, team: team, admin: admin} = ctx
    conn = log_in_user(conn, admin)

    assert_error_sent 404, fn -> get(conn, ~p"/teams/#{team}/photos/abc/file") end
    assert_error_sent 404, fn -> get(conn, ~p"/teams/#{team}/photos/999999999/file") end
  end
end
