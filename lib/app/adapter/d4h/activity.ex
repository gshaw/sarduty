defmodule App.Adapter.D4H.Activity do
  defstruct activity_id: nil,
            team_id: nil,
            ref_id: nil,
            is_published: false,
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
      activity_id: record["id"],
      team_id: record["team_id"],
      ref_id: record["ref_autoid"],
      is_published: record["published"] != 0,
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
