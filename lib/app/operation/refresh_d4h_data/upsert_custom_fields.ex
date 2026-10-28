defmodule App.Operation.RefreshD4HData.UpsertCustomFields do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Operation.RefreshD4HData.StaleRows
  alias App.Repo

  require Logger

  @doc """
  Fetches the team's custom fields and its organisation's (#681) and keeps a copy in
  `custom_fields`. A field D4H deleted is deleted here too; the values on records stay,
  named by their D4H id.
  """
  def call(d4h, team) do
    save(team.id, D4H.fetch_custom_fields(d4h), DateTime.utc_now())
  end

  def save(team_id, d4h_fields, now) do
    rows =
      d4h_fields
      |> Enum.uniq_by(& &1.d4h_custom_field_id)
      |> Enum.map(fn field ->
        field
        |> Map.from_struct()
        |> Map.merge(%{team_id: team_id, inserted_at: now, updated_at: now})
      end)

    rows
    |> Enum.chunk_every(100)
    |> Enum.each(
      &Repo.insert_all(CustomField, &1,
        on_conflict: {:replace_all_except, [:id, :team_id, :d4h_custom_field_id, :inserted_at]},
        conflict_target: [:team_id, :d4h_custom_field_id]
      )
    )

    delete_stale(team_id, MapSet.new(rows, & &1.d4h_custom_field_id))
  end

  defp delete_stale(team_id, synced_d4h_ids) do
    stale_ids =
      CustomField
      |> where([f], f.team_id == ^team_id)
      |> StaleRows.ids(:d4h_custom_field_id, synced_d4h_ids)

    if stale_ids != [] do
      {count, _} = CustomField |> where([f], f.id in ^stale_ids) |> Repo.delete_all()
      Logger.info("Deleted #{count} stale custom fields for team #{team_id}")
    end
  end
end
