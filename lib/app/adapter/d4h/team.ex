defmodule App.Adapter.D4H.Team do
  alias App.Adapter.D4H.Parse

  # `custom_values` are the team's own field values (#1056 step 5), as a member's are.
  defstruct d4h_team_id: nil,
            name: nil,
            subdomain: nil,
            coordinate: nil,
            timezone: nil,
            custom_values: %{}

  def build(record) do
    %__MODULE__{
      d4h_team_id: record["id"],
      name: record["title"],
      subdomain: record["subdomain"],
      coordinate: Parse.coordinate(record["location"]),
      timezone: record["timezone"],
      custom_values: Parse.custom_values(record["customFieldValues"])
    }
  end
end
