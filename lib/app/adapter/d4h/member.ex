defmodule App.Adapter.D4H.Member do
  alias App.Adapter.D4H.Parse

  defstruct d4h_member_id: nil,
            d4h_team_id: nil,
            ref_id: nil,
            name: nil,
            position: nil,
            email: nil,
            phone: nil,
            address: nil,
            joined_at: nil,
            left_at: nil,
            permission: nil,
            status: nil

  def build(record) do
    %__MODULE__{
      d4h_member_id: record["id"],
      d4h_team_id: Parse.team_id(record["owner"]),
      name: record["name"],
      position: record["position"],
      ref_id: record["ref"],
      email: String.downcase(record["email"]["value"] || ""),
      phone: record["mobile"]["phone"],
      address: record["deprecatedAddress"],
      joined_at: Parse.optional_datetime(record["startsAt"]),
      left_at: Parse.optional_datetime(record["endsAt"]),
      permission: record["permission"],
      status: record["status"]
    }
  end
end
