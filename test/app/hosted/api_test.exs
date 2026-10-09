defmodule App.Hosted.APITest do
  use App.DataCase, async: true

  import Plug.Conn
  import Plug.Test

  alias App.Adapter.D4H
  alias App.Hosted
  alias App.Hosted.API
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.RefreshD4HData
  alias App.Operation.SyncD4HChanges

  setup do
    unique = System.unique_integer([:positive])

    {:ok, hosted, key} =
      Hosted.create_team(%{
        title: "Nova #{unique}",
        subdomain: "nova#{unique}",
        timezone: "America/Halifax"
      })

    %{hosted: hosted, key: key}
  end

  defp call(method, path, key, body \\ nil) do
    conn = conn(method, path, body && Jason.encode!(body))
    conn = if body, do: put_req_header(conn, "content-type", "application/json"), else: conn
    conn = if key, do: put_req_header(conn, "authorization", "Bearer #{key}"), else: conn
    conn = API.call(conn, API.init([]))
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp path(hosted, rest), do: "/v3/team/#{hosted.id}/#{rest}"

  defp create!(hosted, key, resource, body) do
    {200, row} = call(:post, path(hosted, resource), key, body)
    row
  end

  test "a request without the team's key is refused", %{hosted: hosted, key: key} do
    assert {401, %{"title" => "Unauthorized"}} = call(:get, path(hosted, "members"), nil)
    assert {401, _} = call(:get, path(hosted, "members"), "sdh_wrong")
    assert {200, %{"totalSize" => 0}} = call(:get, path(hosted, "members"), key)
  end

  test "a key reaches only its own team", %{hosted: hosted, key: key} do
    {:ok, other, other_key} =
      Hosted.create_team(%{title: "Other", subdomain: "other#{hosted.id}", timezone: "UTC"})

    member =
      create!(other, other_key, "members", %{name: "Pat", startsAt: "2026-01-01T00:00:00Z"})

    assert {403, _} = call(:get, path(other, "members"), key)
    assert {403, _} = call(:patch, path(other, "members/#{member["id"]}"), key, %{name: "X"})
    assert {404, _} = call(:get, path(hosted, "members/#{member["id"]}"), key)

    event =
      create!(hosted, key, "events", %{
        startsAt: "2026-02-01T18:00:00Z",
        endsAt: "2026-02-01T21:00:00Z"
      })

    assert {400, %{"title" => "Unknown member."}} =
             call(:post, path(hosted, "attendance"), key, %{
               memberId: member["id"],
               activityId: event["id"],
               startsAt: "2026-02-01T18:00:00Z",
               endsAt: "2026-02-01T21:00:00Z"
             })
  end

  test "hosted ids never match a D4H team's", %{hosted: hosted} do
    assert hosted.id >= 2_000_000_000
  end

  test "a tag on an activity can't be deleted", %{hosted: hosted, key: key} do
    tag = create!(hosted, key, "tags", %{title: "Primary Hours"})

    event =
      create!(hosted, key, "events", %{
        startsAt: "2026-02-01T18:00:00Z",
        endsAt: "2026-02-01T21:00:00Z"
      })

    {200, _} =
      call(:post, path(hosted, "events/#{event["id"]}/tags"), key, %{tagIds: [tag["id"]]})

    assert {400, _} = call(:delete, path(hosted, "tags/#{tag["id"]}"), key)
  end

  test "an odd query parameter is a 400", %{hosted: hosted, key: key} do
    assert {400, _} = call(:get, path(hosted, "attendance?member_id[a]=1"), key)
  end

  test "whoami names the team as a SAR Duty account", %{hosted: hosted, key: key} do
    assert {200, body} = call(:get, "/v3/whoami", key)
    whoami = D4H.WhoAmI.build(body)
    assert whoami.d4h_team_id == hosted.id
    assert whoami.member_name == "SAR Duty"
  end

  test "lists page and sort as D4H's do", %{hosted: hosted, key: key} do
    for n <- 1..5, do: create!(hosted, key, "member-groups", %{title: "Group #{n}"})

    assert {200, %{"totalSize" => 5, "results" => [_, _]}} =
             call(:get, path(hosted, "member-groups?page=1&size=2"), key)

    assert {200, %{"results" => [%{"title" => "Group 5"}]}} =
             call(:get, path(hosted, "member-groups?sort=updatedAt&order=desc&size=1"), key)
  end

  test "a bad body is a 400 with D4H's title", %{hosted: hosted, key: key} do
    assert {400, %{"title" => "name can't be blank" <> _}} =
             call(:post, path(hosted, "members"), key, %{ref: "1"})
  end

  test "a deleted activity leaves the lists, with its attendance", %{hosted: hosted, key: key} do
    member = create!(hosted, key, "members", %{name: "Pat", startsAt: "2026-01-01T00:00:00Z"})

    event =
      create!(hosted, key, "events", %{
        referenceDescription: "Training",
        startsAt: "2026-02-01T18:00:00Z",
        endsAt: "2026-02-01T21:00:00Z"
      })

    assert event["reference"] == "00001"

    create!(hosted, key, "attendance", %{
      memberId: member["id"],
      activityId: event["id"],
      status: "ATTENDING",
      startsAt: "2026-02-01T18:00:00Z",
      endsAt: "2026-02-01T21:00:00Z"
    })

    assert {200, %{"totalSize" => 1}} = call(:get, path(hosted, "attendance"), key)
    assert {200, _} = call(:delete, path(hosted, "events/#{event["id"]}"), key)
    assert {404, _} = call(:get, path(hosted, "events/#{event["id"]}"), key)
    assert {200, %{"totalSize" => 0}} = call(:get, path(hosted, "events"), key)
    assert {200, %{"totalSize" => 0}} = call(:get, path(hosted, "attendance"), key)
  end

  test "the refresh and the sync copy a hosted team as they copy D4H", %{hosted: hosted, key: key} do
    team =
      Team.insert!(%{
        name: hosted.title,
        subdomain: hosted.subdomain,
        d4h_team_id: hosted.id,
        d4h_api_host: D4H.hosted_host(),
        d4h_access_key: key,
        lat: 44.6,
        lng: -63.6,
        timezone: hosted.timezone
      })

    pat =
      create!(hosted, key, "members", %{
        name: "Pat Example",
        email: "pat@example.com",
        phone: %{mobile: "902-555-0100"},
        permission: "OWNER",
        startsAt: "2026-01-01T00:00:00Z"
      })

    primary = create!(hosted, key, "tags", %{title: Activity.primary_hours_tag()})

    exercise =
      create!(hosted, key, "exercises", %{
        referenceDescription: "Night search",
        address: %{town: "Truro", region: "NS"},
        location: %{latitude: 45.36, longitude: -63.28},
        startsAt: "2026-03-01T22:00:00Z",
        endsAt: "2026-03-02T02:00:00Z"
      })

    {200, _} =
      call(:post, path(hosted, "exercises/#{exercise["id"]}/tags"), key, %{
        tagIds: [primary["id"]]
      })

    create!(hosted, key, "attendance", %{
      memberId: pat["id"],
      activityId: exercise["id"],
      status: "ATTENDING",
      startsAt: "2026-03-01T22:00:00Z",
      endsAt: "2026-03-02T02:00:00Z"
    })

    assert {:ok, team, _missed} = RefreshD4HData.call(team)
    assert team.d4h_access_key_owner == "SAR Duty"

    member = Repo.get_by!(Member, team_id: team.id, d4h_member_id: pat["id"])
    assert member.email == "pat@example.com"
    assert member.phone == "902-555-0100"
    assert Team.managed_by?(team, "pat@example.com", DateTime.utc_now())

    activity = Repo.get_by!(Activity, team_id: team.id, d4h_activity_id: exercise["id"])
    assert activity.title == "Night search"
    assert activity.address == "Truro, NS"
    assert activity.tags == [Activity.primary_hours_tag()]
    assert Repo.get_by!(Attendance, activity_id: activity.id).duration_in_minutes == 240

    {200, _} = call(:patch, path(hosted, "members/#{pat["id"]}"), key, %{name: "Pat Renamed"})
    {200, _} = call(:patch, path(hosted, "members/#{pat["id"]}/retire"), key, %{})

    assert {:ok, _team, changed} = team.id |> Team.get!() |> SyncD4HChanges.call()
    assert "members" in changed
    member = Repo.reload!(member)
    assert member.name == "Pat Renamed"
    assert member.d4h_status == "RETIRED"
    refute Team.managed_by?(team, "pat@example.com", DateTime.utc_now())
  end
end
