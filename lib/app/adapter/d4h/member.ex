defmodule App.Adapter.D4H.Member do
  defstruct d4h_member_id: nil,
            d4h_team_id: nil,
            ref_id: nil,
            name: nil,
            position: nil,
            email: nil,
            phone: nil,
            address: nil,
            joined_at: nil,
            left_at: nil

  def build(record) do
    %__MODULE__{
      d4h_member_id: record["id"],
      d4h_team_id: record["team_id"],
      name: record["name"],
      position: record["position"],
      ref_id: record["ref"],
      email: (record["email"] || "") |> String.downcase(),
      phone: record["mobilephone"],
      address: record["address"],
      joined_at: parse_optional_datetime(record["joined_at"]),
      left_at: parse_optional_datetime(record["left_at"])
    }
  end

  defp parse_optional_datetime(nil), do: nil

  defp parse_optional_datetime(value) do
    {:ok, result, 0} = DateTime.from_iso8601(value)
    DateTime.truncate(result, :second)
  end
end
