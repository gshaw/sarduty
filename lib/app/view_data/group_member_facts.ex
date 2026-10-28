defmodule App.ViewData.GroupMemberFacts do
  @moduledoc """
  What a group page's Members table shows beside each name: the member's standing today
  and when they last attended, by member id. Members who never attended have no entry in
  `last_attended`.
  """
  import Ecto.Query

  alias App.Model.Member
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Repo

  def load(%Team{} = team, members, now) do
    ids = Enum.map(members, & &1.id)

    query =
      from(row in subquery(Member.last_attended_query(team, now)),
        where: row.member_id in ^ids,
        select: {row.member_id, type(row.last_attended_at, :utc_datetime)}
      )

    last_attended = query |> Repo.all() |> Map.new()

    %{standing: Standing.by_member(team, members, now), last_attended: last_attended}
  end
end
