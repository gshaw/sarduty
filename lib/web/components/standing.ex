defmodule Web.Components.Standing do
  @moduledoc "A member's standing (#366) as people read it."

  alias App.Model.MemberAwayPeriod

  @doc ~s{The standing as text: "Active", "Away until March 1, 2027 (Parental)", or "Not a person".}
  def text(:active), do: "Active"
  def text(:not_a_person), do: "Not a person"

  def text({:away, period}),
    do:
      "Away until #{Service.Format.day_long(period.ends_on)} (#{MemberAwayPeriod.reason_label(period.reason)})"
end
