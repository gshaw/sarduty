defmodule App.ViewData.WaitingChores do
  @moduledoc """
  The rows of Waiting on Chores (#1102). Chores logged together that still wait are one
  row, everyone in it A to Z; any other chore is a row of its own. Pure: chores in, rows
  out.

  A row reads as its first chore by name: its date, words, and category. Each chore
  changed on its own page since stays in the row, and `differs` says what is different
  about it.
  """

  alias Service.Format

  @doc """
  The rows, oldest first, each `%{id:, first:, chores:, ids:, minutes:, minutes_each:,
  differs:}`. `id` is its first chore's, which the row's box sends. `minutes` is the total,
  and `minutes_each` the minutes when there are several chores and all are the same, else
  nil. `differs` has a line for each chore unlike the first, "Riley Okafor: 2 hours". The
  chores need their members and categories.
  """
  def rows(chores) do
    chores
    |> Enum.group_by(&(&1.logged_together_id || {:alone, &1.id}))
    |> Enum.map(fn {_key, chores} -> row(by_name(chores)) end)
    |> Enum.sort_by(& &1.first.id)
    |> Enum.sort_by(& &1.first.date, Date)
  end

  defp by_name(chores), do: Enum.sort_by(chores, &{String.downcase(&1.member.name), &1.id})

  defp row([first | _rest] = chores) do
    minutes = Enum.map(chores, & &1.minutes)

    %{
      id: first.id,
      first: first,
      chores: chores,
      ids: Enum.map(chores, & &1.id),
      minutes: Enum.sum(minutes),
      minutes_each: if(length(chores) > 1 and length(Enum.uniq(minutes)) == 1, do: first.minutes),
      differs: for(chore <- chores, line = differs(first, chore), do: line)
    }
  end

  defp differs(first, chore) do
    case first |> values(chore) |> Enum.reject(&is_nil/1) do
      [] -> nil
      values -> "#{chore.member.name}: #{Enum.join(values, ", ")}"
    end
  end

  defp values(first, chore) do
    [
      chore.date != first.date && Format.date_short(chore.date),
      chore.minutes != first.minutes && Format.duration(chore.minutes),
      chore.chore_category_id != first.chore_category_id && chore.chore_category.title,
      chore.description != first.description && chore.description
    ]
    |> Enum.map(&(&1 || nil))
  end
end
