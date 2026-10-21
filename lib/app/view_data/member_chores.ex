defmodule App.ViewData.MemberChores do
  @moduledoc """
  A member's Chores page (#341): their chores by month, with totals, and the year's
  numbers. Pure: chores in, rows out. Each chore stays its own row; nothing is rolled up.
  """

  @doc """
  The chores by the month they were done, newest month first, each with its minutes by
  status: `%{month: first_day, chores:, accepted:, waiting:, declined:}`.
  """
  def months(chores) do
    chores
    |> Enum.group_by(&Date.beginning_of_month(&1.date))
    |> Enum.sort_by(fn {month, _chores} -> month end, {:desc, Date})
    |> Enum.map(fn {month, chores} ->
      chores
      |> totals()
      |> Map.merge(%{month: month, chores: Enum.sort_by(chores, &{&1.date, &1.id}, :desc)})
    end)
  end

  @doc "Minutes by status: `%{accepted:, waiting:, declined:}`."
  def totals(chores) do
    base = %{accepted: 0, waiting: 0, declined: 0}
    Enum.reduce(chores, base, &Map.update!(&2, &1.status, fn m -> m + &1.minutes end))
  end

  @doc """
  The year's numbers: accepted minutes and chores done in `year`, and minutes waiting
  from any year. `%{accepted_minutes:, accepted_count:, waiting_minutes:}`.
  """
  def stats(chores, year) do
    accepted = Enum.filter(chores, &(&1.status == :accepted and &1.date.year == year))

    %{
      accepted_minutes: accepted |> Enum.map(& &1.minutes) |> Enum.sum(),
      accepted_count: length(accepted),
      waiting_minutes:
        chores |> Enum.filter(&(&1.status == :waiting)) |> Enum.map(& &1.minutes) |> Enum.sum()
    }
  end
end
