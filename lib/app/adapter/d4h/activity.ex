defmodule App.Adapter.D4H.Activity do
  alias App.Model.Coordinate

  defstruct d4h_activity_id: nil,
            d4h_team_id: nil,
            ref_id: nil,
            is_published: false,
            title: nil,
            description: nil,
            address: nil,
            coordinate: nil,
            started_at: nil,
            finished_at: nil,
            activity_kind: nil,
            tags: []

  def build(record) do
    {:ok, started_at, 0} = DateTime.from_iso8601(record["date"])
    {:ok, finished_at, 0} = DateTime.from_iso8601(record["enddate"])

    %__MODULE__{
      d4h_activity_id: record["id"],
      d4h_team_id: record["team_id"],
      ref_id: record["ref_autoid"],
      is_published: record["published"] != 0,
      title: String.slice(record["ref_desc"], 0, 50),
      description: record["description"],
      address: build_address(record),
      coordinate: Coordinate.build(record),
      started_at: started_at,
      finished_at: finished_at,
      activity_kind: record["activity"],
      tags: record["tags"]
    }
  end

  defp build_address(record) do
    [
      record["streetaddress"],
      record["townaddress"],
      record["regionaddress"],
      record["countryaddress"]
    ]
    |> Enum.reject(&String.match?(&1, ~r/^\s*$/))
    |> Enum.join(", ")
  end
end
