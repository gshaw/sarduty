defmodule App.Operation.RefreshD4HData.UpsertWhiteboardNotes do
  @moduledoc """
  Copies the team's whiteboard (#515): every note, in one transaction, keyed by D4H id
  so a note keeps its local id and a form open on it still works. Notes D4H no longer
  has go. Runs in the full refresh every night, and in the sync when the whiteboard's
  head moved.

  A 403 means the team has the module off. It saves no notes and turns
  `whiteboard_enabled` off, which hides the card and the pages. It never reaches the
  sync's rejected-key rescue, which would stop every sync for the team.
  """

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Model.WhiteboardNote
  alias App.Repo

  require Logger

  @doc "Returns the team, with `whiteboard_enabled` as the read found it."
  def call(d4h, %Team{} = team) do
    case D4H.fetch_whiteboard_notes(d4h) do
      {:ok, notes} ->
        {:ok, :ok} = Repo.transaction(fn -> replace(team.id, notes) end)
        Logger.info("Copied #{length(notes)} whiteboard notes for team #{team.id}")
        set_enabled(team, true)

      :off ->
        set_enabled(team, false)
    end
  end

  defp replace(team_id, notes) do
    now = DateTime.utc_now()

    rows =
      Enum.map(notes, fn note ->
        note
        |> WhiteboardNote.fields_from()
        |> Map.merge(%{team_id: team_id, inserted_at: now, updated_at: now})
      end)

    # SQLite takes at most 32,766 parameters a statement, and a row has 11.
    for chunk <- Enum.chunk_every(rows, 1000) do
      Repo.insert_all(WhiteboardNote, chunk,
        on_conflict: {:replace_all_except, [:id, :team_id, :inserted_at]},
        conflict_target: [:team_id, :d4h_whiteboard_note_id]
      )
    end

    ids = Enum.map(notes, & &1.d4h_whiteboard_note_id)

    WhiteboardNote
    |> where([n], n.team_id == ^team_id and n.d4h_whiteboard_note_id not in ^ids)
    |> Repo.delete_all()

    :ok
  end

  defp set_enabled(%Team{whiteboard_enabled: enabled} = team, enabled), do: team

  defp set_enabled(team, enabled) do
    Logger.info("Whiteboard #{if enabled, do: "on", else: "off"} for team #{team.id}")
    team |> Ecto.Changeset.change(whiteboard_enabled: enabled) |> Repo.update!()
  end
end
