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

  @doc """
  Whether the award starts on `date`, its UTC date (#493). D4H keeps an award's dates as
  midnight UTC, and SAR Duty's own start at midnight on the team's clock: the same UTC
  date in every Canadian time zone. The date on the team's clock would be the day before
  for nearly every award D4H has.
  """
  def starts_on?(%__MODULE__{starts_at: %DateTime{} = starts_at}, %Date{} = date),
    do: DateTime.to_date(starts_at) == date

  def starts_on?(%__MODULE__{}, _date), do: false
end
