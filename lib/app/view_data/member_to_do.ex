defmodule App.ViewData.MemberToDo do
  @moduledoc """
  "For you to do" on the Dashboard (#389, #406): each item stays until it's done. Pure:
  what SAR Duty knows about the member in, items out.

  - `:card`: their ID card, until it's in Wallet (`MemberCard.in_wallet?/1`).
  - `:qualification`: each one expiring within 60 days, until it's renewed, or while a
    certificate for it waits (#493).
  - `:declined_chores`: their declined chores (#341), until they delete them.
  - `:declined_certificates`: their declined certificates (#493), until they delete them.
  - `:travel`: each activity whose travel a team admin set for them (#230), until they
    check it, or that they attended with no travel set, until they set it. Either way
    only until the activity is published.
  """

  @doc """
  Items in that order. `card` is the member's current card or nil, and `rows` their
  qualifications from `MemberRecords.qualification_rows/2`.
  `extras` may hold `chores:` their chores, `certificates:` the certificates they sent and
  haven't deleted, `trips:` their unchecked trips on open activities, each with its
  activity (`Trip.unchecked_for_member/1`), and `unset:` their attended rows with no trip
  (`Trip.unset_for_member/2`).
  """
  def items(card, in_wallet?, rows, extras \\ []) do
    chores = Keyword.get(extras, :chores, [])
    certificates = Keyword.get(extras, :certificates, [])
    trips = Keyword.get(extras, :trips, [])
    unset = Keyword.get(extras, :unset, [])

    card_items(card, in_wallet?) ++
      qualification_items(rows, certificates) ++
      declined_items(chores) ++
      declined_certificate_items(certificates) ++
      travel_items(trips, unset)
  end

  # One per activity, oldest first: `trips` a team admin set to check, and `unset` rows
  # with nothing set.
  defp travel_items(trips, unset) do
    trips = Enum.group_by(trips, & &1.activity_id)
    unset = Enum.group_by(unset, & &1.activity_id)

    (Map.values(trips) ++ Map.values(unset))
    |> Enum.map(&hd(&1).activity)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.started_at, DateTime)
    |> Enum.map(fn activity ->
      %{
        key: :travel,
        activity: activity,
        trips: Map.get(trips, activity.id, []),
        unset: Map.get(unset, activity.id, [])
      }
    end)
  end

  defp declined_certificate_items(certificates) do
    case Enum.filter(certificates, &(&1.status == :declined)) do
      [] -> []
      declined -> [%{key: :declined_certificates, certificates: declined}]
    end
  end

  defp declined_items(chores) do
    case Enum.filter(chores, &(&1.status == :declined)) do
      [] -> []
      declined -> [%{key: :declined_chores, chores: declined}]
    end
  end

  defp card_items(nil, _in_wallet?), do: []
  defp card_items(_card, true), do: []
  defp card_items(card, false), do: [%{key: :card, card: card}]

  defp qualification_items(rows, certificates) do
    waiting =
      for %{status: :waiting} = c <- certificates, into: MapSet.new(), do: c.qualification_id

    for %{status: :expiring, award: award, days_left: days} <- rows,
        not MapSet.member?(waiting, Map.get(award, :qualification_id)) do
      %{key: :qualification, award: award, days: days}
    end
  end
end
