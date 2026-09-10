defmodule App.Adapter.D4H.WhoAmI do
  alias App.Adapter.D4H.Parse

  # d4h_team_id is the first membership's team; d4h_team_ids is every team the
  # key's member belongs to.
  defstruct d4h_team_id: nil,
            d4h_team_ids: [],
            d4h_member_id: nil,
            hasAccess: false,
            member_name: nil,
            team_name: nil

  def build(record) when is_map(record) do
    with {:ok, members} <- Map.fetch(record, "members"),
         [member | _] <- members,
         {:ok, team} <- Map.fetch(member, "owner") do
      %__MODULE__{
        d4h_team_id: Parse.team_id(team),
        d4h_team_ids: team_ids(members),
        d4h_member_id: Parse.member_id(member),
        hasAccess: member["hasAccess"],
        member_name: member["name"],
        team_name: team["title"]
      }
    else
      _ -> nil
    end
  end

  defp team_ids(members) do
    members
    |> Enum.map(&Parse.team_id(&1["owner"] || %{}))
    |> Enum.reject(&is_nil/1)
  end
end
