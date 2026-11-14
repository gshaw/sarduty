defmodule Web.Settings.TeamLogoLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSetRow
  alias App.Model.Team
  alias App.RecordsStub
  alias App.Repo

  defp upload(lv, name, content, type) do
    lv
    |> file_input("#logo-form", :logo, [%{name: name, content: content, type: type}])
    |> render_upload(name)
  end

  defp put_logo(team, bytes) do
    path = Team.logo_path(team.subdomain)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
  end

  describe "on a Records team" do
    setup %{conn: conn} do
      %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
      on_exit(fn -> team.subdomain |> Team.logo_path() |> File.rm() end)
      %{conn: log_in_user(conn, user), team: team}
    end

    test "Change logo is in General's Actions", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings")

      assert has_element?(
               lv,
               ~s|#team-logo-change[href="/teams/#{team.subdomain}/settings/logo"]|
             )
    end

    test "a logo goes to Records as a PNG up to 1024 px, and SAR Duty keeps a copy at once",
         %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {200, %{"id" => 5}} end)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/logo")
      assert has_element?(lv, "#team-logo-none")
      upload(lv, "logo.png", png_fixture(2000, 1000), "image/png")

      {:ok, _page, html} = lv |> form("#logo-form") |> render_submit() |> follow_redirect(conn)
      assert html =~ "Logo saved."

      path = "/teams/#{team.d4h_team_id}/image"
      assert_received {:records, "PUT", ^path, {:bytes, <<0x89, "PNG", _rest::binary>> = png}}
      image = Image.from_binary!(png)
      assert {Image.width(image), Image.height(image)} == {1024, 512}

      [row] = Repo.all(ChangeSetRow)
      assert {row.action, row.status} == {:set_team_logo, :applied}
      assert team.subdomain |> Team.logo_file() |> File.read!() == png
      assert Repo.reload!(team).logo_at
    end

    test "Remove logo deletes it in Records and here", %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {200, %{}} end)
      put_logo(team, png_fixture(40, 40))
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/logo")

      assert has_element?(
               lv,
               ~s|#download-logo[href="/teams/#{team.subdomain}/settings/logo/original"]|
             )

      {:ok, _page, html} =
        lv |> element("#remove-logo") |> render_click() |> follow_redirect(conn)

      assert html =~ "Logo removed."
      path = "/teams/#{team.d4h_team_id}/image"
      assert_received {:records, "DELETE", ^path, nil}
      assert Team.logo_file(team.subdomain) == nil
    end

    test "a file that isn't an image says so, and nothing is sent", %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {200, %{}} end)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/logo")
      upload(lv, "logo.png", "not an image", "image/png")

      lv |> form("#logo-form") |> render_submit()
      assert has_element?(lv, "#flash-error", "SAR Duty cannot read this logo.")
      refute_received {:records, _method, _path, _body}
    end

    test "Download original logo sends the saved file", %{conn: conn, team: team} do
      png = png_fixture(40, 40)
      put_logo(team, png)

      conn = get(conn, ~p"/teams/#{team}/settings/logo/original")
      assert response(conn, 200) == png
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
    end
  end

  describe "on a D4H team" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "d4h_key"}})
      on_exit(fn -> team.subdomain |> Team.logo_path() |> File.rm() end)
      %{conn: log_in_user(conn, user), team: team}
    end

    test "a logo goes to D4H as the team's profile document, and the old one goes",
         %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {200, %{"id" => 99}} end, %{
        "/documents" => [%{"id" => 11}]
      })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/logo")
      upload(lv, "logo.png", png_fixture(40, 30), "image/png")

      {:ok, _page, html} = lv |> form("#logo-form") |> render_submit() |> follow_redirect(conn)
      assert html =~ "Logo saved."

      assert_received {:records, "POST", "/documents", {:multipart, form}}
      assert form =~ ~s(name="targetResourceType"\r\n\r\nTeam)
      assert form =~ ~s(name="targetResourceId"\r\n\r\n#{team.d4h_team_id})
      assert form =~ ~s(name="profile"\r\n\r\ntrue)
      assert_received {:records, "DELETE", "/documents/11", nil}
    end

    test "D4H's refusal shows in the toast, and no copy is saved", %{conn: conn, team: team} do
      RecordsStub.stub(fn _method, _path, _body -> {403, %{"title" => "Forbidden"}} end)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/logo")
      upload(lv, "logo.png", png_fixture(40, 30), "image/png")

      assert lv |> form("#logo-form") |> render_submit() =~ "D4H refused it"
      assert Team.logo_file(team.subdomain) == nil
    end
  end
end
