defmodule App.ViewData.MemberToDo do
  @moduledoc """
  "For you to do" on the Dashboard (#389, #406): each item stays until it's done. Pure:
  what SAR Duty knows about the member in, items out.

  - `:card`: their ID card, until it's in Wallet (`MemberCard.in_wallet?/1`).
  - `:qualification`: each one expiring within 60 days, until it's renewed, or while a
    certificate for it waits (#493).
  - `:letter`: last year's tax credit letter, or this year's, until they download it, and
    only in letter season, January to April, when people file. The rest of the year it
    waits on Your membership.
  - `:declined_chores`: their declined chores (#341), until they delete them.
  - `:declined_certificates`: their declined certificates (#493), until they delete them.
  - `:travel`: each activity whose travel a team admin set for them (#230), until they
    check it or the activity is published.
  """

  @doc """
  Items in that order. `card` is the member's current card or nil, `letters` their tax
  credit letters, and `rows` their qualifications from `MemberRecords.qualification_rows/2`.
  `extras` may hold `chores:` their chores, `certificates:` the certificates they sent and
  haven't deleted, and `trips:` their unchecked trips on open activities, each with its
  activity (`Trip.unchecked_for_member/1`).
  """
  def items(card, in_wallet?, letters, rows, now, timezone, extras \\ []) do
    chores = Keyword.get(extras, :chores, [])
    certificates = Keyword.get(extras, :certificates, [])
    trips = Keyword.get(extras, :trips, [])

    card_items(card, in_wallet?) ++
      qualification_items(rows, certificates) ++
      declined_items(chores) ++
      declined_certificate_items(certificates) ++
      travel_items(trips) ++ letter_items(letters, now, timezone)
  end

  # One per activity, in the order the trips come.
  defp travel_items(trips) do
    trips
    |> Enum.chunk_by(& &1.activity_id)
    |> Enum.map(fn [trip | _] = trips ->
      %{key: :travel, activity: trip.activity, trips: trips}
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

  # Only the newest letter, and only a recent one: a member who never downloaded their
  # 2019 letter has nothing to do about it now.
  defp letter_items(letters, now, timezone) do
    recent = Service.YearRange.year_in(now, timezone) - 1

    case Service.Period.letter_season?(now, timezone) &&
           Enum.max_by(letters, & &1.year, fn -> nil end) do
      %{year: year, downloaded_at: nil} = letter when year >= recent ->
        [%{key: :letter, letter: letter}]

      _other ->
        []
    end
  end
end
