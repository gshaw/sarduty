defmodule App.Operation.PlanEndorsements do
  @moduledoc """
  Turns one team's group rule clauses into endorsements, for the migration that
  introduces them (#320). Every group keeps a rule that admits exactly the same members.

  - Clauses with the same qualifications become one endorsement, whatever their names.
  - When one name covers different qualifications, the longest list keeps it, so cards
    read as they did. The others stay off cards.
  - A list without a name of its own is named after its qualifications when that fits in
    60 characters, or else "Name – Group", or else after its group.
  - A clause with no qualifications is dropped. It made its group plan no changes, and in
    production each one is the only clause in its group, so those groups stay without a
    rule (checked 2026-10-13).

  Delete this module with the old clause tables.
  """

  @max 60

  @doc """
  Pure. `clauses` are `%{id, d4h_group_id, name, on_card, qualification_ids}`; `titles`
  and `group_titles` are keyed by D4H id. Returns
  `%{name, on_card, qualification_ids, d4h_group_ids}` for each endorsement.
  """
  def plan(clauses, titles, group_titles) do
    sets =
      clauses
      |> Enum.reject(&(&1.qualification_ids == []))
      |> Enum.group_by(&MapSet.new(&1.qualification_ids))
      |> Enum.sort_by(fn {_set, cs} -> cs |> Enum.map(& &1.id) |> Enum.min() end)

    owners = owners(sets)
    names = {titles, group_titles}

    # Names clauses already use are reserved, so a made-up name never takes one.
    {endorsements, _taken} =
      Enum.map_reduce(sets, owners |> Map.keys() |> MapSet.new(), fn {set, cs}, taken ->
        endorsement = endorsement(set, cs, owners, names, taken)
        {endorsement, MapSet.put(taken, endorsement.name)}
      end)

    endorsements
  end

  defp endorsement(set, cs, owners, {titles, group_titles}, taken) do
    owned = cs |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.filter(&(owners[&1] == set))

    name =
      if owned == [],
        do: cs |> pick_name(set, titles, group_titles, taken) |> unique(taken),
        else: pick_owned(cs, owned)

    %{
      name: name,
      on_card: Enum.any?(cs, &(&1.on_card and &1.name in owned)),
      qualification_ids: set |> MapSet.to_list() |> Enum.sort(),
      d4h_group_ids: cs |> Enum.map(& &1.d4h_group_id) |> Enum.uniq()
    }
  end

  # Each name goes to the set with the most qualifications among those that use it, then
  # the one using it most, then the oldest.
  defp owners(sets) do
    sets
    |> Enum.flat_map(&uses/1)
    |> Enum.group_by(& &1.name)
    |> Map.new(fn {name, uses} ->
      {name, Enum.min_by(uses, &{-MapSet.size(&1.set), -&1.count, &1.id}).set}
    end)
  end

  defp uses({set, cs}) do
    for c <- cs,
        present?(c.name),
        do: %{name: c.name, set: set, count: Enum.count(cs, &(&1.name == c.name)), id: c.id}
  end

  defp pick_owned(cs, owned) do
    Enum.min_by(owned, fn name ->
      named = Enum.filter(cs, &(&1.name == name))
      {not Enum.any?(named, & &1.on_card), -length(named), name}
    end)
  end

  defp pick_name(cs, set, titles, group_titles, taken) do
    from_titles = titles_name(set, titles)
    first = hd(cs)
    group = group_titles |> Map.get(first.d4h_group_id, "Group") |> trim_group()
    named = Enum.find(cs, &present?(&1.name))

    cond do
      from_titles && not MapSet.member?(taken, from_titles) -> from_titles
      named -> fit("#{named.name} – #{group}")
      true -> fit(group)
    end
  end

  defp titles_name(set, titles) do
    names = Enum.map(set, &titles[&1])

    if Enum.all?(names, & &1) do
      name = names |> Enum.sort() |> Enum.join(" or ")
      if String.length(name) <= @max, do: name
    end
  end

  # Group titles on South Fraser start with "!!" to sort first in D4H.
  defp trim_group(title), do: title |> String.trim_leading("!") |> String.trim()

  defp unique(name, taken), do: unique(name, taken, 1)

  defp unique(name, taken, n) do
    candidate = if n == 1, do: name, else: fit(name, " (#{n})")
    if MapSet.member?(taken, candidate), do: unique(name, taken, n + 1), else: candidate
  end

  defp fit(name, suffix \\ ""),
    do: String.slice(name, 0, @max - String.length(suffix)) <> suffix

  defp present?(name), do: is_binary(name) and name != ""
end
