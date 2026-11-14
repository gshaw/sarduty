defmodule App.Operation.RefreshD4HDataTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Team
  alias App.Operation.RefreshD4HData

  test "a team without a key isn't refreshed" do
    assert RefreshD4HData.call(team_fixture()) == {:error, :no_key}
  end

  describe "save_logo/3" do
    setup do
      team = team_fixture()
      on_exit(fn -> team.subdomain |> Team.logo_path() |> File.rm() end)
      %{team: team}
    end

    test "moves logo_at only when the bytes change", %{team: team} do
      first = ~U[2026-11-13 10:00:00.000000Z]
      later = ~U[2026-11-14 10:00:00.000000Z]

      team = RefreshD4HData.save_logo(team, {:ok, "logo one", "logo.png"}, first)
      assert team.logo_at == first
      assert team.subdomain |> Team.logo_file() |> File.read!() == "logo one"

      team = RefreshD4HData.save_logo(team, {:ok, "logo one", "logo.png"}, later)
      assert Repo.reload!(team).logo_at == first

      team = RefreshD4HData.save_logo(team, {:ok, "logo two", "logo.png"}, later)
      assert Repo.reload!(team).logo_at == later
    end

    test "gives a logo saved before logo_at its first one", %{team: team} do
      team_logo_fixture(team, "old logo")
      now = ~U[2026-11-13 10:00:00.000000Z]

      assert RefreshD4HData.save_logo(team, {:ok, "old logo", "logo.png"}, now).logo_at == now
    end

    test "a logo removed in D4H removes the file and clears logo_at", %{team: team} do
      team = RefreshD4HData.save_logo(team, {:ok, "logo", "logo.png"}, DateTime.utc_now())

      team = RefreshD4HData.save_logo(team, :none, DateTime.utc_now())

      assert Repo.reload!(team).logo_at == nil
      assert Team.logo_file(team.subdomain) == nil
    end
  end

  # Nothing else copies them, so a team that moves or changes its time zone in D4H or
  # Records sees it the next morning (#1076). The names stay the team's own (#738).
  test "a full refresh copies the team's place and time zone, not its names" do
    team = team_fixture(%{d4h_access_key: "key", d4h_team_id: 77})
    on_exit(fn -> team.subdomain |> Team.logo_path() |> File.rm() end)

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      if conn.request_path =~ ~r{/teams/77$} do
        Req.Test.json(conn, %{
          "id" => 77,
          "title" => "Renamed SAR",
          "timezone" => "America/Toronto",
          "location" => %{"type" => "Point", "coordinates" => [-79.4, 43.7]}
        })
      else
        Req.Test.json(conn, %{"results" => [], "totalSize" => 0, "page" => 0})
      end
    end)

    assert {:ok, _team, _missed} = RefreshD4HData.call(team)
    assert %{timezone: "America/Toronto", lat: 43.7, lng: -79.4} = refreshed = Repo.reload!(team)
    assert refreshed.name == team.name
  end

  test "a key D4H rejects comes back as an error for a person to fix" do
    team = team_fixture(%{d4h_access_key: "expired-key"})
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 401, ""))

    assert RefreshD4HData.call(team) == {:error, {:key_rejected, 401}}

    assert RefreshD4HData.error_message(team, {:key_rejected, 401}) ==
             "D4H refused your access key (401). Save a new one in team settings."
  end
end
