defmodule App.Operation.SeedCoastRange do
  @moduledoc """
  Inserts Coast Range SAR (App.CoastRange) into `repo`: App.SampleRepo at boot and every
  night, and App.Repo when a mockup or test seeds the cast (Web.MockupSeed). Rows go in
  the order build/1 gives them, each with its links' ids and the team's. insert/3 does the
  same for any cast's rows, such as Silver Basin SAR's (App.SilverBasin).
  """

  alias App.CoastRange

  @doc """
  Inserts the cast as of `now`, with `team_attrs` on the team, and returns every row by
  `{kind, key}`: `{:team, :coastrange}`, `{:member, "Alex Chen"}`, `{:activity, d4h_id}`.
  """
  def call(repo, %DateTime{} = now, team_attrs \\ %{}),
    do: insert(repo, CoastRange.build(now), team_attrs)

  @doc "Inserts a cast's `rows`, the team's first, as call/3 does Coast Range's."
  def insert(repo, [{:team, team_key, _team, []} | _rest] = rows, team_attrs \\ %{}) do
    Enum.reduce(rows, %{}, fn {kind, key, row, links}, inserted ->
      row = put_links(row, kind, links, inserted, inserted[{:team, team_key}], team_attrs)
      Map.put(inserted, {kind, key}, repo.insert!(row))
    end)
  end

  defp put_links(team, :team, [], _rows, nil, team_attrs), do: struct!(team, team_attrs)

  defp put_links(row, _kind, links, rows, team, _team_attrs) do
    row = if Map.has_key?(row, :team_id), do: %{row | team_id: team.id}, else: row

    Enum.reduce(links, row, fn {field, ref}, row ->
      Map.put(row, field, Map.fetch!(rows, ref).id)
    end)
  end
end
