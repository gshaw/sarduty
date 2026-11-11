defmodule App.Operation.BuildYetToArrive do
  # Who signed up for an activity and has no scan at the door yet (#245), so the person
  # at the door can call them, and who is here now (#998), so they can record them
  # leaving with a tap. Pure: the caller loads the members and scans. Any scan counts
  # for Yet to arrive, so a member scanned leaving drops off too.

  @doc """
  `%{yet_to_arrive: [member], here: [scan], signed_up: n, arrived: n, walk_ins: n}` from
  the members D4H shows as signed up and the door's scans, oldest first. `yet_to_arrive`
  is ordered by name; `here` is each member whose latest scan is an arrival, that scan
  with its member, ordered by name. `walk_ins` counts members with a scan who did not
  sign up.
  """
  def call(signed_up, scans) do
    scanned_ids = MapSet.new(scans, & &1.member_id)
    signed_up_ids = MapSet.new(signed_up, & &1.id)

    %{
      yet_to_arrive:
        signed_up
        |> Enum.reject(&(&1.id in scanned_ids))
        |> Enum.sort_by(&String.downcase(&1.name)),
      here: here(scans),
      signed_up: MapSet.size(signed_up_ids),
      arrived: MapSet.size(scanned_ids),
      walk_ins: scanned_ids |> MapSet.difference(signed_up_ids) |> MapSet.size()
    }
  end

  # A member who left and came back is here again: only the latest scan counts.
  defp here(scans) do
    scans
    |> Enum.group_by(& &1.member_id)
    |> Enum.map(fn {_member_id, member_scans} -> List.last(member_scans) end)
    |> Enum.filter(&(&1.kind == "arrived"))
    |> Enum.sort_by(&String.downcase(&1.member.name))
  end
end
