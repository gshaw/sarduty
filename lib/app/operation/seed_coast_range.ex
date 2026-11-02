defmodule App.Operation.SeedCoastRange do
  @moduledoc """
  Inserts Coast Range SAR (App.CoastRange) into `repo`: App.SampleRepo at boot and every
  night, and App.Repo when a mockup or test seeds the cast (Web.MockupSeed). Rows go in
  the order build/1 gives them, each with its links' ids and the team's.
  """

  alias App.CoastRange

  @doc """
  Inserts the cast as of `now`, with `team_attrs` on the team, and returns every row by
  `{kind, key}`: `{:team, :coastrange}`, `{:member, "Alex Chen"}`, `{:activity, d4h_id}`.
  """
  def call(repo, %DateTime{} = now, team_attrs \\ %{}) do
    now
    |> CoastRange.build()
    |> Enum.reduce(%{}, fn {kind, key, row, links}, rows ->
      inserted = row |> put_links(kind, links, rows, team_attrs) |> repo.insert!()
      Map.put(rows, {kind, key}, inserted)
    end)
  end

  defp put_links(team, :team, [], _rows, team_attrs), do: struct!(team, team_attrs)

  defp put_links(row, _kind, links, rows, _team_attrs) do
    row =
      if Map.has_key?(row, :team_id),
        do: %{row | team_id: rows[{:team, :coastrange}].id},
        else: row

    Enum.reduce(links, row, fn {field, ref}, row ->
      Map.put(row, field, Map.fetch!(rows, ref).id)
    end)
  end
end
