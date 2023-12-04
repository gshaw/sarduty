defmodule Service.D4H do
  alias Service.D4H

  def build_config() do
    %{
      access_token: System.get_env("D4H_ACCESS_TOKEN"),
      api_host: "api.ca.d4h.org"
    }
  end

  def build_config(access_token: access_token, api_host: api_host) do
    %{
      access_token: access_token,
      api_host: api_host
    }
  end

  def get!(path) do
    d4h = build_config()
    Req.get!("https://#{d4h.api_host}/v2/#{path}", auth: {:bearer, d4h.access_token})
  end

  def get!(d4h, path) do
    Req.get!("https://#{d4h.api_host}/v2/#{path}", auth: {:bearer, d4h.access_token})
  end

  def fetch!(d4h, path) do
    get!(d4h, path).body["data"]
  end

  def fetch_activity!(d4h, activity_id) do
    d4h
    |> fetch!("team/activities/#{activity_id}")
    |> D4H.Activity.build()
  end

  def fetch_attendance!(d4h, activity_id) do
    team_members = fetch_team_members!(d4h)

    d4h
    |> fetch!("team/attendance?activity_id=#{activity_id}")
    |> Enum.filter(fn r -> r["status"] == "attending" end)
    |> Enum.map(&D4H.Attendance.build(&1, team_members))
    |> Enum.sort(fn a, b -> a.member.name < b.member.name end)
  end

  def fetch_team_members!(d4h) do
    d4h
    |> fetch!("team/members")
    |> Enum.map(&D4H.Member.build(&1))
    |> Enum.sort(fn a, b -> a.name < b.name end)
  end
