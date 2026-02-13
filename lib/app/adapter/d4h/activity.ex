defmodule App.Adapter.D4H.Activity do
  alias App.Adapter.D4H.Parse

  defstruct d4h_activity_id: nil,
            d4h_team_id: nil,
            ref_id: nil,
            tracking_number: nil,
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
    build(record, nil)
  end

  def build(record, tag_index) do
    %__MODULE__{
      d4h_activity_id: record["id"],
      d4h_team_id: Parse.team_id(record["owner"]),
      ref_id: record["reference"],
      tracking_number: record["trackingNumber"],
      is_published: record["published"],
      title: build_title(record["referenceDescription"], record["id"]),
      # Note: description in v3 is HTML
      description: record["description"],
      address: build_address(record["address"]),
      coordinate: Parse.coordinate(record["location"]),
      started_at: Parse.datetime(record["startsAt"]),
      finished_at: Parse.datetime(record["endsAt"]),
      activity_kind: Parse.activity_kind(record["resourceType"]),
      tags: Parse.tag_ids(record["tags"], tag_index)
    }
  end

  defp build_title(nil, activity_id), do: "Untitled Activity #{activity_id}"
  defp build_title("", activity_id), do: "Untitled Activity #{activity_id}"
  defp build_title(description, _), do: String.slice(description, 0, 50)

  defp build_address(record) do
    [
      record["street"],
      record["town"],
      record["region"],
      record["country"]
    ]
    |> Enum.reject(fn str -> is_nil(str) or String.match?(str, ~r/^\s*$/) end)
    |> Enum.join(", ")
  end
end
