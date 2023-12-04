defmodule Service.D4H.Activity do
  defstruct d4h_activity_id: nil,
            d4h_team_id: nil,
            ref_id: nil,
            title: nil,
            description: nil,
            lat: nil,
            lng: nil,
            started_at: nil,
            finished_at: nil,
            kind: nil

  def build(record) do
    {:ok, started_at, 0} = DateTime.from_iso8601(record["date"])
    {:ok, finished_at, 0} = DateTime.from_iso8601(record["enddate"])

    %__MODULE__{
      d4h_activity_id: record["id"],
      d4h_team_id: record["team_id"],
      ref_id: record["ref_autoid"],
      title: record["ref_desc"],
      description: record["description"],
      lat: record["lat"],
      lng: record["lng"],
      started_at: started_at,
      finished_at: finished_at,
      kind: record["activity"]
    }
  end
end
