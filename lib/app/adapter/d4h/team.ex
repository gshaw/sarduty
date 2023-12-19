defmodule App.Adapter.D4H.Team do
  defstruct d4h_team_id: nil,
            d4h_organisation_id: nil,
            name: nil,
            subdomain: nil,
            coordinate: nil,
            timezone: nil

  alias App.Model.Coordinate

  def build(record) do
    %__MODULE__{
      d4h_team_id: record["id"],
      d4h_organisation_id: record["organisation_id"],
      name: record["title"],
      subdomain: record["subdomain"],
      coordinate: Coordinate.build(record),
      timezone: record["timezone"]["location"]
    }
  end
end
