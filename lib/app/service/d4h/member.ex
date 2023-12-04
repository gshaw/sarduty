defmodule Service.D4H.Member do
  defstruct d4h_member_id: nil,
            d4h_team_id: nil,
            ref_id: nil,
            name: nil,
            position: nil,
            email: nil,
            phone: nil,
            address: nil

  def build(record) do
    %__MODULE__{
      d4h_member_id: record["id"],
      d4h_team_id: record["team_id"],
      name: record["name"],
      position: record["position"],
      ref_id: record["ref"],
      email: record["email"],
      phone: record["mobilephone"],
      address: record["address"]
    }
  end
end
