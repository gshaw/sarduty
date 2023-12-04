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

# "plan" => "",
# "location_bookmark_id" => 1242,
# "id" => 239_224,
# "postcodeaddress" => "",
# "countryaddress" => "Canada",
# "ref_desc" => "Training night - Office",
# "latlng" => "49.107879413084,-122.82894365717",
# "enddate" => "2023-12-01T06:00:00.000Z",
# "updated_at" => "2023-12-01T08:12:35.000Z",
# "created_at" => "2023-10-27T20:36:26.000Z",
# "archived" => 0,
# "attendance_type" => "full",
# "regionaddress" => "British Columbia",
# "published" => 1,
# "tags" => ["Primary Hours", "Core Training Hours", "Regular Training"],
# "tracking_number" => "",
# "count_guests" => 0,
# "lng" => -122.82894365717,
# "activity" => "exercise",
# "description_html" => "<p>Cold weather mitigation with Justin Bennett.</p>",
# "weather" => nil,
# "distance" => 811,
# "ref" => "01302 Training night - Office",
# "townaddress" => "Surrey",
# "bearing" => 263,
# "description" => "Cold weather mitigation with Justin Bennett.",
# "streetaddress" => "5756 142 ST",
# "ref_autoid" => "01302",
# "count_attendance" => 16,
# "date" => "2023-12-01T03:00:00.000Z",
# "night" => 1,
# "count_equipment_used" => 0,
# "lat" => 49.107879413084,
# "team_id" => 422,
# "gridref" => "",
# "plan_html" => nil,
# "perc_attendance" => 22
# }
