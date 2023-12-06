defmodule App.Adapter.D4H.Member do
  defstruct member_id: nil,
            team_id: nil,
            ref_id: nil,
            name: nil,
            position: nil,
            email: nil,
            phone: nil,
            address: nil

  def build(record) do
    %__MODULE__{
      member_id: record["id"],
      team_id: record["team_id"],
      name: record["name"],
      position: record["position"],
      ref_id: record["ref"],
      email: record["email"] |> String.downcase(),
      phone: record["mobilephone"],
      address: record["address"]
    }
  end
end
