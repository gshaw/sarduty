defmodule App.Adapter.D4H.GroupMembership do
  alias App.Adapter.D4H.Parse

  defstruct d4h_group_membership_id: nil,
            d4h_member_id: nil,
            d4h_group_id: nil

  def build(record) do
    %__MODULE__{
      d4h_group_membership_id: record["id"],
      d4h_member_id: Parse.member_id(record["member"]),
      d4h_group_id: record["group"]["id"]
    }
  end
end
