defmodule App.Adapter.D4H.Team do
  alias App.Model.Coordinate

  defstruct d4h_team_id: nil,
            d4h_organisation_id: nil,
            name: nil,
            subdomain: nil,
            coordinate: nil,
            timezone: nil

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
