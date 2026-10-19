defmodule Web.Components.Standing do
  @moduledoc "A member's standing (#366) as people read it."

  alias App.Model.MemberAwayPeriod

  @doc ~s{The standing as text: "Active", "Away until March 1, 2027 (Parental leave)", "Not a person", or "Retired".}
  defdelegate text(standing), to: MemberAwayPeriod, as: :describe_standing
end
