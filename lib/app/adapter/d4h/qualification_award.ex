defmodule App.Adapter.D4H.QualificationAward do
  alias App.Adapter.D4H.Parse

  defstruct d4h_award_id: nil,
            d4h_member_id: nil,
            d4h_qualification_id: nil,
            starts_at: nil,
            ends_at: nil

  def build(record) do
    %__MODULE__{
      d4h_award_id: record["id"],
      d4h_member_id: Parse.member_id(record["member"]),
      d4h_qualification_id: record["qualification"]["id"],
      starts_at: Parse.optional_datetime(record["startsAt"]),
      ends_at: Parse.optional_datetime(record["endsAt"])
    }
  end
end
