defmodule Web.MemberPagesSweepTest do
  # Every page a member sees, opened as every member, against a copy of a real database
  # (#425). Not part of the suite: `mix sweep.member_pages` runs it, and its moduledoc
  # says how. A SAR Duty admin, made in the sandbox, views as each member in turn.
  use Web.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
  alias App.DataFixtures
  alias App.Model.Member
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.ViewData.MemberRecords

  @moduletag :sweep
  @moduletag timeout: :infinity

  test "every member page opens for every member" do
    # Pages that read D4H or Mapbox get a 404, as when the service has no such record.
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))
    Req.Test.stub(App.Adapter.Mapbox, &Plug.Conn.send_resp(&1, 404, ""))
    Process.flag(:trap_exit, true)

    admin = DataFixtures.make_admin(AccountsFixtures.user_fixture())
    token = App.Accounts.generate_user_session_token(admin)
    now = DateTime.utc_now()

    results =
      for team <- teams(), result <- sweep_team(team, token, now), do: result

    failures =
      for {team, member, path, {:error, reason}} <- results, do: {team, member, path, reason}

    members = results |> Enum.map(fn {_t, member, _p, _r} -> member.id end) |> Enum.uniq()

    Mix.shell().info(
      "\nOpened #{length(results)} pages for #{length(members)} members. #{length(failures)} failed."
    )

    for {team, member, path, reason} <- failures do
      Mix.shell().info("#{team.subdomain} member #{member.id} #{path}\n  #{reason}")
    end

    if failures != [], do: flunk("Pages failed: #{length(failures)}. They are listed above.")
  end

  defp sweep_team(team, token, now) do
    members = Member.get_all(team.id)
    Mix.shell().info("#{team.subdomain}: #{length(members)} members")

    for member <- members,
        member = %{member | team: team},
        path <- paths(team, member, now) do
      conn = Phoenix.ConnTest.init_test_session(build_conn(), %{})
      conn = conn |> put_session(:user_token, token) |> put_session(:view_as_member_id, member.id)
      {team, member, path, check(conn, path)}
    end
  end

  defp teams do
    case System.get_env("SWEEP_TEAM", "") do
      "" -> Team.get_all()
      subdomain -> [Team.get_by(subdomain: subdomain) || raise("No team #{subdomain}")]
    end
  end

  defp paths(team, member, now) do
    years = MemberRecords.years_on_team(member, now)
    letters = TaxCreditLetter.get_all_for_member(member)

    [
      ~p"/teams/#{team}",
      ~p"/teams/#{team}/activities",
      ~p"/teams/#{team}/me",
      ~p"/teams/#{team}/me/details"
    ] ++
      Enum.map(years, &~p"/teams/#{team}/me/activities?year=#{&1}") ++
      Enum.map(letters, &~p"/teams/#{team}/me/tax-credit-letters/#{&1.id}/pdf")
  end

  # :ok, or {:error, reason} in one line. Crash logs are kept out of the report.
  defp check(conn, path) do
    {result, _log} = with_log(fn -> open(conn, path) end)
    result
  end

  defp open(conn, path) do
    if String.ends_with?(path, "/pdf"), do: download(conn, path), else: live_page(conn, path)
  rescue
    error -> {:error, error |> Exception.message() |> one_line()}
  catch
    :exit, reason -> {:error, "exit: " <> one_line(inspect(reason))}
  end

  defp live_page(conn, path) do
    case live(conn, path) do
      {:ok, lv, _html} ->
        render_async(lv, 5_000)
        render(lv)
        GenServer.stop(lv.pid)
        :ok

      {:error, {kind, %{to: to}}} ->
        {:error, "#{kind} to #{to}"}
    end
  end

  defp download(conn, path) do
    case get(conn, path) do
      %{status: 200} -> :ok
      conn -> {:error, "status #{conn.status}"}
    end
  end

  defp one_line(text), do: text |> String.split("\n") |> List.first() |> String.slice(0, 300)
end
