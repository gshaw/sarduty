defmodule App.Adapter.D4H.WhoAmI do
  alias App.Adapter.D4H.Parse

  # d4h_team_id is the first membership's team; d4h_team_ids is every team the
  # key's member belongs to, and member_names and member_ids their name and id on each.
  defstruct d4h_team_id: nil,
            d4h_team_ids: [],
            member_names: %{},
            member_ids: %{},
            d4h_member_id: nil,
            hasAccess: false,
            member_name: nil,
            team_name: nil

  def build(record) when is_map(record) do
    with {:ok, members} <- Map.fetch(record, "members"),
         [member | _] <- members,
         {:ok, team} <- Map.fetch(member, "owner") do
      build(members, member, team)
    else
      _ -> nil
    end
  end

  defp build(members, member, team) do
    %__MODULE__{
      d4h_team_id: Parse.team_id(team),
      d4h_team_ids: team_ids(members),
      member_names: by_team(members, & &1["name"]),
      member_ids: by_team(members, &Parse.member_id/1),
      d4h_member_id: Parse.member_id(member),
      hasAccess: member["hasAccess"],
      member_name: member["name"],
      team_name: team["title"]
    }
  end

  @doc "The key's member name on the given D4H team, or nil."
  def member_name(%__MODULE__{} = whoami, d4h_team_id),
    do: Map.get(whoami.member_names, d4h_team_id)

  @doc "The key's member id on the given D4H team, or nil."
  def member_id(%__MODULE__{} = whoami, d4h_team_id),
    do: Map.get(whoami.member_ids, d4h_team_id)

  defp by_team(members, value) do
    for member <- members,
        team_id = Parse.team_id(member["owner"] || %{}),
        team_id != nil,
        into: %{},
        do: {team_id, value.(member)}
  end

  defp team_ids(members) do
    members
    |> Enum.map(&Parse.team_id(&1["owner"] || %{}))
    |> Enum.reject(&is_nil/1)
  end
end
