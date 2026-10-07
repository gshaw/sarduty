defmodule App.MCP.Tool.ListMembers do
  @moduledoc """
  Every member, current and left, with position and group names. No contact details.
  """
  @behaviour App.MCP.Tool

  import Ecto.Query

  alias App.MCP.Output
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  @impl App.MCP.Tool
  def name, do: "list_members"

  @impl App.MCP.Tool
  def description do
    "Every member of the team, including those who left: id, name, position, the D4H " <>
      "groups they are in, when they joined and left, and their D4H status. Position and " <>
      "groups are where a team records categories such as MIT or Provisional. No email, " <>
      "phone, or address."
  end

  @impl App.MCP.Tool
  def input_schema, do: %{"type" => "object", "properties" => %{}}

  @impl App.MCP.Tool
  def fields, do: ~w(id name position groups joined_at left_at d4h_status)

  @impl App.MCP.Tool
  def call(%Team{} = team, _args, _now) do
    members = build(load_members(team), load_group_names(team), team.timezone)
    {:ok, members, length(members)}
  end

  @doc """
  The output for `members`, by name. `group_names` are `{member_id, group title}` pairs.
  """
  def build(members, group_names, timezone) do
    groups =
      group_names
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {id, titles} -> {id, Enum.sort(titles)} end)

    members
    |> Enum.sort_by(&{&1.name, &1.id})
    |> Enum.map(fn member ->
      %{
        "id" => member.id,
        "name" => member.name,
        "position" => member.position,
        "groups" => Map.get(groups, member.id, []),
        "joined_at" => Output.datetime(member.joined_at, timezone),
        "left_at" => Output.datetime(member.left_at, timezone),
        "d4h_status" => member.d4h_status
      }
    end)
  end

  defp load_members(team) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> select([m], map(m, [:id, :name, :position, :joined_at, :left_at, :d4h_status]))
    |> Repo.all()
  end

  defp load_group_names(team) do
    GroupMember
    |> join(:inner, [gm], g in Group, on: g.id == gm.group_id)
    |> join(:inner, [gm], m in Member, on: m.id == gm.member_id)
    |> where([gm, g, m], g.team_id == ^team.id and m.team_id == ^team.id)
    |> select([gm, g], {gm.member_id, g.title})
    |> Repo.all()
  end
end
