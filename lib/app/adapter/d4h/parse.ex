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

  def tag_id(%{"resourceType" => "Tag", "id" => id}), do: id
  def tag_id(%{}), do: nil

  def tag_ids(tags, tag_index) do
    tags
    |> Enum.map(&tag_id(&1))
    |> Enum.uniq()
    |> Enum.map(&look_up_tag_title(tag_index, &1))
  end

  defp look_up_tag_title(nil, tag_id), do: Integer.to_string(tag_id)
  defp look_up_tag_title(tag_index, tag_id), do: tag_index[tag_id]

  def team_id(%{"resourceType" => "Team", "id" => id}), do: id
  def team_id(%{}), do: nil

  @doc "D4H's address parts as one line, the street first and the postcode left out."
  def address(%{} = record) do
    [record["street"], record["town"], record["region"], record["country"]]
    |> Enum.reject(fn str -> is_nil(str) or String.match?(str, ~r/^\s*$/) end)
    |> Enum.join(", ")
  end

  def address(_record), do: ""

  def coordinate(%{"coordinates" => [lng, lat]}) do
    Coordinate.build(lat, lng)
  end

  def coordinate(_location), do: nil

  def datetime(value) do
    {:ok, result, 0} = DateTime.from_iso8601(value)
    DateTime.truncate(result, :second)
  end

  @doc "A D4H time to the microsecond, or nil, for comparing change times."
  def precise_datetime(nil), do: nil

  def precise_datetime(value) do
    {:ok, result, 0} = DateTime.from_iso8601(value)
    result
  end

  def optional_datetime(nil), do: nil
  def optional_datetime(value), do: datetime(value)

  @doc """
  A record's custom field values (#681) as a map of the D4H field id, a string, to its
  value: a string, or a list of option ids for a choice field. Empty values are left
  out, so a field D4H clears drops out of the map.
  """
  def custom_values(values) when is_list(values) do
    for %{"customField" => %{"id" => id}, "value" => value} <- values,
        value not in [nil, "", []],
        into: %{},
        do: {Integer.to_string(id), value}
  end

  def custom_values(_values), do: %{}
end
