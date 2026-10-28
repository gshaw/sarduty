defmodule App.Adapter.D4H.CustomField do
  alias App.Adapter.D4H.Parse

  # One of D4H's custom fields (#681): the team's own or its organisation's. Only the
  # targets SAR Duty copies are built; the rest come back nil.
  defstruct d4h_custom_field_id: nil,
            target: nil,
            title: nil,
            field_type: nil,
            required: false,
            restricted: false,
            member_privacy: nil,
            hint: nil,
            value_units: nil,
            ordering: 0,
            owner_type: nil,
            owner_id: nil,
            archived_at: nil,
            options: []

  @targets %{
    "Event" => "event",
    "Exercise" => "exercise",
    "Incident" => "incident",
    "Member" => "member",
    "Equipment" => "equipment"
  }

  def targets, do: Map.values(@targets)

  def build(record) do
    case @targets[record["targetResourceType"]] do
      nil -> nil
      target -> build(record, target)
    end
  end

  defp build(record, target) do
    owner = if is_map(record["owner"]), do: record["owner"], else: %{}

    %__MODULE__{
      d4h_custom_field_id: record["id"],
      target: target,
      title: record["title"],
      field_type: downcase(record["type"] || "TEXT"),
      required: record["mandatory"] == true,
      restricted: record["restricted"] == "RESTRICTED",
      member_privacy: downcase(record["memberPrivacy"]),
      hint: blank_to_nil(record["hint"]),
      value_units: blank_to_nil(record["valueUnits"]),
      ordering: record["ordering"] || 0,
      owner_type: owner["resourceType"],
      owner_id: owner["id"],
      archived_at: Parse.optional_datetime(record["archivedAt"]),
      options: Enum.map(record["options"] || [], &option/1)
    }
  end

  defp option(record) do
    %{
      "id" => record["id"],
      "label" => record["label"],
      "ordering" => record["ordering"] || 0,
      "archived" => record["archivedAt"] != nil
    }
  end

  defp downcase(nil), do: nil
  defp downcase(value), do: String.downcase(value)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
