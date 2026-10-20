defmodule App.ViewData.MemberToDo do
  @moduledoc """
  "For you to do" on a member's overview (#389): each item stays until it's done. Pure:
  what SAR Duty knows about the member in, items out.

  - `:card`: their ID card, until it's in Wallet (`MemberCard.in_wallet?/1`).
  - `:qualification`: each one expiring within 60 days, until it's renewed.
  - `:letter`: last year's tax credit letter, or this year's, until they download it.
  """

  @doc """
  Items in that order. `card` is the member's current card or nil, `letters` their tax
  credit letters, and `groups` their qualifications from `MemberRecords.group_awards/2`.
  """
  def items(card, in_wallet?, letters, groups, now, timezone) do
    card_items(card, in_wallet?) ++
      qualification_items(groups, now) ++ letter_items(letters, now, timezone)
  end

  defp card_items(nil, _in_wallet?), do: []
  defp card_items(_card, true), do: []
  defp card_items(card, false), do: [%{key: :card, card: card}]

  defp qualification_items(groups, now) do
    for {:within_60_days, rows} <- groups, %{award: award} <- rows do
      %{key: :qualification, award: award, days: days_left(award.ends_at, now)}
    end
  end

  # Whole days, rounded up, so an award ending tomorrow afternoon has 1 day left.
  defp days_left(ends_at, now), do: ceil(DateTime.diff(ends_at, now) / 86_400)

  # Only the newest letter, and only a recent one: a member who never downloaded their
  # 2019 letter has nothing to do about it now.
  defp letter_items(letters, now, timezone) do
    recent = Service.YearRange.year_in(now, timezone) - 1

    case Enum.max_by(letters, & &1.year, fn -> nil end) do
      %{year: year, downloaded_at: nil} = letter when year >= recent ->
        [%{key: :letter, letter: letter}]

      _other ->
        []
    end
  end
end
