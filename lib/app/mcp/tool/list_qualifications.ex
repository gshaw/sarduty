defmodule App.MCP.Tool.ListQualifications do
  @moduledoc "The team's qualifications, each with every member's awards and expiry."
  @behaviour App.MCP.Tool

  import Ecto.Query

  alias App.MCP.Output
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Repo

  @impl App.MCP.Tool
  def name, do: "list_qualifications"

  @impl App.MCP.Tool
  def description do
    "The team's qualifications by title, each with the awards members hold: member id " <>
      "and name, start, expiry (null when it never expires), and status: current, " <>
      "expired, or not_started. A member who renewed has one award per renewal."
  end

  @impl App.MCP.Tool
  def input_schema, do: %{"type" => "object", "properties" => %{}}

  @impl App.MCP.Tool
  def fields do
    ~w(id title awards member_id member_name starts_at ends_at status)
  end

  @impl App.MCP.Tool
  def call(%Team{} = team, _args, now) do
    qualifications = build(load_qualifications(team), load_awards(team), team.timezone, now)
    {:ok, qualifications, length(qualifications)}
  end

  @doc """
  The output for `qualifications`, by title. `awards` have `qualification_id`,
  `member_id`, `member_name`, `starts_at`, and `ends_at`.
  """
  def build(qualifications, awards, timezone, now) do
    awards_by_qualification = Enum.group_by(awards, & &1.qualification_id)

    qualifications
    |> Enum.sort_by(&{&1.title, &1.id})
    |> Enum.map(fn qualification ->
      %{
        "id" => qualification.id,
        "title" => qualification.title,
        "awards" =>
          awards_by_qualification
          |> Map.get(qualification.id, [])
          |> Enum.sort_by(&{&1.member_name, &1.member_id, sort_time(&1.starts_at)})
          |> Enum.map(&award(&1, timezone, now))
      }
    end)
  end

  defp award(award, timezone, now) do
    %{
      "member_id" => award.member_id,
      "member_name" => award.member_name,
      "starts_at" => Output.datetime(award.starts_at, timezone),
      "ends_at" => Output.datetime(award.ends_at, timezone),
      "status" => status(award, now)
    }
  end

  defp status(award, now) do
    cond do
      MemberQualificationAward.active?(award, now) -> "current"
      MemberQualificationAward.expired?(award, now) -> "expired"
      true -> "not_started"
    end
  end

  defp sort_time(nil), do: 0
  defp sort_time(%DateTime{} = datetime), do: DateTime.to_unix(datetime)

  defp load_qualifications(team) do
    Qualification
    |> where([q], q.team_id == ^team.id)
    |> select([q], map(q, [:id, :title]))
    |> Repo.all()
  end

  defp load_awards(team) do
    MemberQualificationAward
    |> join(:inner, [aw], m in Member, on: m.id == aw.member_id)
    |> join(:inner, [aw], q in Qualification, on: q.id == aw.qualification_id)
    |> where([aw, m, q], m.team_id == ^team.id and q.team_id == ^team.id)
    |> select([aw, m], %{
      qualification_id: aw.qualification_id,
      member_id: m.id,
      member_name: m.name,
      starts_at: aw.starts_at,
      ends_at: aw.ends_at
    })
    |> Repo.all()
  end
end
