defmodule App.Adapter.D4H.LocationBookmark do
  alias App.Adapter.D4H.Parse

  defstruct d4h_location_bookmark_id: nil,
            title: nil,
            address: nil,
            coordinate: nil,
            archived_at: nil

  # A named place (#614). Its address is joined as an activity's is.
  def build(record) do
    %__MODULE__{
      d4h_location_bookmark_id: record["id"],
      title: record["title"],
      address: Parse.address(record["address"]),
      coordinate: Parse.coordinate(record["location"]),
      archived_at: Parse.optional_datetime(record["archivedAt"])
    }
  end
end
