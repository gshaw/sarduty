defmodule Web.ReportControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  test "Download CSV gives the page's rows, unformatted", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{name: "Chen, Avery"})

    exercise =
      activity_fixture(team, %{activity_kind: "exercise", started_at: ~U[2025-03-01 18:00:00Z]})

    incident =
      activity_fixture(team, %{activity_kind: "incident", started_at: ~U[2025-04-01 18:00:00Z]})

    attendance_fixture(exercise, member, %{duration_in_minutes: 150})
    attendance_fixture(incident, member, %{duration_in_minutes: 60})

    conn =
      conn |> log_in_user(user) |> get(~p"/teams/#{team}/reports/hours-by-member/csv?year=2025")

    assert response_content_type(conn, :csv)

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="#{team.subdomain}-report-hours-by-member.csv")
           ]

    assert response(conn, 200) ==
             "Member,Incident,Exercise,Total\r\n" <>
               "\"Chen, Avery\",1.00,2.50,3.50\r\n" <>
               "Total,1.00,2.50,3.50\r\n"
  end

  # A header can be a label or a pivot value someone typed, or blank for a plain value.
  test "the header row is safe from formulas and takes a blank label" do
    team = team_fixture()
    activity_fixture(team, %{ref_id: "A1"})

    {:ok, result} =
      App.Report.run("select 'x', ref_id from activities label ref_id '=1+1'", team)

    assert Web.ReportCSV.build(result, %{}, team.timezone) == ",'=1+1\r\nx,A1\r\n"
  end

  test "a member who logs in cannot download a report", %{conn: conn} do
    %{user: user, team: team} = member_with_login_fixture()

    assert_raise Web.Status.NotFound, fn ->
      conn |> log_in_user(user) |> get(~p"/teams/#{team}/reports/hours-by-member/csv")
    end
  end
end
