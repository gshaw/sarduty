defmodule App.Adapter.D4H.Parse do
  alias App.Model.Coordinate

  def activity(%{"resourceType" => resource_type, "id" => id}) do
    case activity_kind(resource_type) do
      nil -> {:error, :unknown_activity_kind}
      activity_kind -> {:ok, id, activity_kind}
    end
  end

  def activity(%{}), do: {:error, :missing_required_keys}

  def activity_kind("Event"), do: "event"
  def activity_kind("Exercise"), do: "exercise"
  def activity_kind("Incident"), do: "incident"
  def activity_kind(_resourceType), do: nil

  def member_id(%{"resourceType" => "Member", "id" => id}), do: id
  def member_id(%{}), do: nil

  def role_id(%{"resourceType" => "Role", "id" => id}), do: id
  def role_id(%{}), do: nil

  def tag_id(%{"resourceType" => "Tag", "id" => id}), do: Integer.to_string(id)
  def tag_id(%{}), do: nil

  def tag_ids(tags) do
    tags |> Enum.map(&tag_id(&1)) |> Enum.uniq()
  end

  def team_id(%{"resourceType" => "Team", "id" => id}), do: id
  def team_id(%{}), do: nil

  def coordinate(%{"coordinates" => [lat, lng]}) do
    Coordinate.build(lat, lng)
  end

  def datetime(value) do
    {:ok, result, 0} = DateTime.from_iso8601(value)
    DateTime.truncate(result, :second)
  end

  def optional_datetime(nil), do: nil
  def optional_datetime(value), do: datetime(value)
end
