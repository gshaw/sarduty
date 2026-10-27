defmodule App.Operation.RefreshD4HData.UpsertLocationBookmarks do
  @moduledoc """
  Copies the team's own location bookmarks (#614) in one transaction, keyed by D4H id.
  Archived ones, and ones D4H no longer has, go. Runs in the full refresh every night,
  and in the sync when the bookmarks' head moved.
  """

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Coordinate
  alias App.Model.LocationBookmark
  alias App.Model.Team
  alias App.Repo

  require Logger

  def call(d4h, %Team{} = team, now \\ DateTime.utc_now()) do
    bookmarks = d4h |> D4H.fetch_location_bookmarks() |> live(now)
    {:ok, :ok} = Repo.transaction(fn -> replace(team.id, bookmarks, now) end)
    Logger.info("Copied #{length(bookmarks)} location bookmarks for team #{team.id}")
  end

  @doc "The bookmarks not yet archived at `now`."
  def live(bookmarks, now) do
    Enum.filter(bookmarks, &(is_nil(&1.archived_at) or DateTime.after?(&1.archived_at, now)))
  end

  defp replace(team_id, bookmarks, now) do
    rows =
      bookmarks
      |> Enum.uniq_by(& &1.d4h_location_bookmark_id)
      |> Enum.map(fn bookmark ->
        %{
          team_id: team_id,
          d4h_location_bookmark_id: bookmark.d4h_location_bookmark_id,
          title: bookmark.title,
          address: bookmark.address,
          coordinate: Coordinate.to_string(bookmark.coordinate, 5),
          inserted_at: now,
          updated_at: now
        }
      end)

    for chunk <- Enum.chunk_every(rows, 1000) do
      Repo.insert_all(LocationBookmark, chunk,
        on_conflict: {:replace, [:title, :address, :coordinate, :updated_at]},
        conflict_target: [:team_id, :d4h_location_bookmark_id]
      )
    end

    ids = Enum.map(rows, & &1.d4h_location_bookmark_id)

    LocationBookmark
    |> where([b], b.team_id == ^team_id and b.d4h_location_bookmark_id not in ^ids)
    |> Repo.delete_all()

    :ok
  end
end
