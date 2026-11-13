defmodule App.Adapter.D4H.QualificationAward do
  alias App.Adapter.D4H.Parse

  # D4H keeps an award's start and end as days (Parse.optional_day/1).
  defstruct d4h_award_id: nil,
            d4h_member_id: nil,
            d4h_qualification_id: nil,
            starts_on: nil,
            ends_on: nil

  def build(record) do
    %__MODULE__{
      d4h_award_id: record["id"],
      d4h_member_id: Parse.member_id(record["member"]),
      d4h_qualification_id: record["qualification"]["id"],
      starts_on: Parse.optional_day(record["startsAt"]),
      ends_on: Parse.optional_day(record["endsAt"])
    }
  end

  @doc "Whether the award starts on `date` (#493)."
  def starts_on?(%__MODULE__{starts_on: %Date{} = starts_on}, %Date{} = date),
    do: starts_on == date

  def starts_on?(%__MODULE__{}, _date), do: false
end
