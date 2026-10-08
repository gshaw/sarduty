defmodule App.Operation.BuildYetToArrive do
  # Who signed up for an activity and has no scan at the door yet (#245), so the person
  # at the door can call them. Pure: the caller loads the members and scans. Any scan
  # counts, so a member scanned leaving drops off too.

  @doc """
  `%{yet_to_arrive: [member], signed_up: n, arrived: n, walk_ins: n}` from the members
  D4H shows as signed up and the door's scans. `yet_to_arrive` is ordered by name;
  `walk_ins` counts members with a scan who did not sign up.
  """
  def call(signed_up, scans) do
    scanned_ids = MapSet.new(scans, & &1.member_id)
    signed_up_ids = MapSet.new(signed_up, & &1.id)

    %{
      yet_to_arrive:
        signed_up
        |> Enum.reject(&(&1.id in scanned_ids))
        |> Enum.sort_by(&String.downcase(&1.name)),
      signed_up: MapSet.size(signed_up_ids),
      arrived: MapSet.size(scanned_ids),
      walk_ins: scanned_ids |> MapSet.difference(signed_up_ids) |> MapSet.size()
    }
  end
end
