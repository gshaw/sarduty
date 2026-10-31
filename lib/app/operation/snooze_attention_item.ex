defmodule App.Operation.SnoozeAttentionItem do
  @moduledoc """
  Snoozes a Needs attention item for the whole team (#751), and ends a snooze with Show
  again. Only the decision is stored: the item stays computed, and the members behind it
  are read from it here, never sent by the browser. No D4H write.
  """

  alias App.Accounts.User
  alias App.Model.AttentionSnooze
  alias App.Model.Team
  alias App.ViewData.TeamDashboardViewData

  @periods [:day, :week, :month]

  def periods, do: @periods

  @doc """
  Snoozes the team's item with the string `key` for `period`, as `user`. Returns
  `{:ok, snooze}`, or `{:error, :not_found}` when the item is gone or cannot be snoozed.
  """
  def call(%Team{} = team, %User{} = user, key, period, now \\ DateTime.utc_now())
      when period in @periods do
    case plan(TeamDashboardViewData.attention_items(team, now), key, period, now) do
      {:ok, %{ids: ids, until: until}} -> {:ok, AttentionSnooze.put!(team, user, key, ids, until)}
      error -> error
    end
  end

  @doc "Show again: ends the team's snooze of the item with the string `key`."
  def show_again(%Team{} = team, key) do
    AttentionSnooze.delete(team, key)
    :ok
  end

  @doc """
  Pure. The snooze of the item with the string `key` among `items`: its sorted `ids`, and
  `until`, a day, a week, or a calendar month after `now`. Only an item with `ids` can be
  snoozed (TeamAttention.can_snooze?/1).
  """
  def plan(items, key, period, now) do
    case Enum.find(items, &(Atom.to_string(&1.key) == key)) do
      %{ids: ids} ->
        {:ok, %{ids: Enum.sort(ids), until: until(now, period)}}

      _missing_or_no_ids ->
        {:error, :not_found}
    end
  end

  defp until(now, :day), do: now |> DateTime.add(1, :day) |> DateTime.truncate(:second)
  defp until(now, :week), do: now |> DateTime.add(7, :day) |> DateTime.truncate(:second)
  defp until(now, :month), do: now |> DateTime.shift(month: 1) |> DateTime.truncate(:second)
end
