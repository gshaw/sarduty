defmodule App.Adapter.D4H.WhoAmI do
  alias App.Adapter.D4H.Parse

  defstruct d4h_team_id: nil,
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
        d4h_member_id: Parse.member_id(member),
        hasAccess: member["hasAccess"],
        member_name: member["name"],
        team_name: team["title"]
      }
    else
      _ -> nil
    end
  end
end
