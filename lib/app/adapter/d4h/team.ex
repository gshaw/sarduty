defmodule App.Adapter.D4H.Team do
  alias App.Adapter.D4H.Parse

  defstruct d4h_team_id: nil,
            name: nil,
            subdomain: nil,
            coordinate: nil,
            timezone: nil

  def build(record) do
    %__MODULE__{
      d4h_team_id: record["id"],
      name: record["title"],
      subdomain: record["subdomain"],
      coordinate: Parse.coordinate(record["location"]),
      timezone: record["timezone"]
    }
  end
end
