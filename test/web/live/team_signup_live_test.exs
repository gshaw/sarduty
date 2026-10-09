defmodule Web.TeamSignupLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.D4H
  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.SignUpTeam

  @d4h_team_id 7700

  defp stub_d4h(member_permission) do
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      send(test, {:req_host, conn.host})

      case conn.request_path do
        "/v3/whoami" ->
          Req.Test.json(conn, %{
            "members" => [
              %{
                "resourceType" => "Member",
                "id" => 900,
                "name" => "SAR Duty",
                "owner" => %{
                  "resourceType" => "Team",
                  "id" => @d4h_team_id,
                  "title" => "Ridge SAR"
                }
              }
            ]
          })

        "/v3/team/7700/teams/7700" ->
          Req.Test.json(conn, %{
            "id" => @d4h_team_id,
            "title" => "Ridge SAR",
            "subdomain" => "ridge",
            "location" => %{"coordinates" => [-123.1, 49.2]},
            "timezone" => "America/Vancouver"
          })

        "/v3/team/7700/members" ->
          Req.Test.json(conn, %{
            "results" => [
              %{
                "id" => 10,
                "name" => "Pat Example",
                "email" => %{"value" => "pat@example.com"},
                "mobile" => %{},
                "startsAt" => "2020-01-01T00:00:00Z",
                "permission" => member_permission,
                "status" => "OPERATIONAL",
                "owner" => %{"resourceType" => "Team", "id" => @d4h_team_id}
              }
            ],
            "totalSize" => 1
          })
      end
    end)
  end

  defp sign_up(conn) do
    {:ok, lv, _html} = live(conn, ~p"/signup")

    lv
    |> form("#signup_form",
      form: %{email: "pat@example.com", api_host: "api.ca.d4h.org", access_key: "team-token"}
    )
    |> render_submit()

    lv
  end

  test "an Owner signs a new team up: it goes live, admins hear, the signer gets a link" do
    user_fixture(%{email: "admin@example.com", is_admin: true})
    stub_d4h(0)

    # Called here rather than through the page: manual mode covers only this process, and
    # the page's process would run the first refresh inline.
    params = %{
      "email" => "pat@example.com",
      "api_host" => "api.ca.d4h.org",
      "access_key" => "team-token"
    }

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, %Team{name: "Ridge SAR"}} = SignUpTeam.call(params)
    end)

    team = Team.get_by(d4h_team_id: @d4h_team_id)
    assert team.subdomain == "ridge"
    assert team.d4h_access_key == "team-token"
    assert team.d4h_access_key_owner == "SAR Duty"

    assert_received {:email, %{subject: "New team on SAR Duty: Ridge SAR", to: admins}}
    assert [{_, "admin@example.com"}] = admins

    assert_received {:email,
                     %{subject: "Your SAR Duty login code: " <> _, to: [{_, "pat@example.com"}]}}
  end

  test "a team on SAR Duty Records signs up with a Records key" do
    stub_d4h(0)

    params = %{
      "email" => "pat@example.com",
      "api_host" => "records.sarduty.com",
      "access_key" => "sdr_team-key"
    }

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, %Team{name: "Ridge SAR"}} = SignUpTeam.call(params)
    end)

    assert_received {:req_host, "records.sarduty.com"}
    team = Team.get_by(d4h_team_id: @d4h_team_id)
    assert team.d4h_api_host == "records.sarduty.com"
    assert D4H.records?(team)
  end

  test "choosing SAR Duty Records changes the page's words", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/signup")
    assert has_element?(lv, "#signup-d4h")
    assert has_element?(lv, "label", "D4H access key")

    lv |> form("#signup_form", form: %{api_host: "records.sarduty.com"}) |> render_change()

    assert has_element?(lv, "#signup-records")
    assert has_element?(lv, "label", "Records access key")
  end

  test "a host off the list is refused", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/signup")

    lv
    |> form("#signup_form", form: %{email: "pat@example.com", access_key: "team-token"})
    |> render_submit(%{form: %{api_host: "evil.example.com"}})

    assert has_element?(lv, "#signup_form", "Select where your team's records are.")
  end

  test "a Member can't sign the team up", %{conn: conn} do
    stub_d4h(2)

    lv = sign_up(conn)
    assert has_element?(lv, "#signup_form", "Use the email of an Owner or Editor")

    refute Team.get_by(d4h_team_id: @d4h_team_id)

    assert %Event{ip: "127.0.0.1", data: %{"fields" => ["email"], "who" => who}} =
             Event.get_last(:team_signup_failed)

    refute who =~ "@"
  end
end
