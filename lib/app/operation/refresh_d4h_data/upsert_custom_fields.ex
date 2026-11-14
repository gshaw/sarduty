defmodule App.Operation.RefreshD4HData.UpsertCustomFields do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.ChangeSetRow
  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle
  alias App.Operation.RefreshD4HData.StaleRows
  alias App.Repo

  require Logger

  @doc """
  Fetches the team's custom fields and its organisation's (#681), and the resource
  bundles that group them (#872), and keeps a copy in `custom_fields` and
  `custom_field_bundles`. A field D4H deleted is deleted here too; the values on records
  stay, named by their D4H id. A bundle D4H deleted goes, and its fields join no bundle.
  """
  def call(d4h, team) do
    save(
      team.id,
      D4H.fetch_resource_bundles(d4h),
      D4H.fetch_custom_fields(d4h),
      DateTime.utc_now()
    )
  end

  def save(team_id, d4h_bundles, d4h_fields, now) do
    bundle_ids = save_bundles(team_id, d4h_bundles, now)

    rows =
      d4h_fields
      |> Enum.uniq_by(& &1.d4h_custom_field_id)
      |> Enum.map(fn field ->
        {d4h_bundle_id, row} = field |> Map.from_struct() |> Map.pop(:d4h_bundle_id)

        Map.merge(row, %{
          team_id: team_id,
          bundle_id: bundle_ids[d4h_bundle_id],
          inserted_at: now,
          updated_at: now
        })
      end)

    upsert(CustomField, rows, [:id, :team_id, :d4h_custom_field_id, :inserted_at], [
      :team_id,
      :d4h_custom_field_id
    ])

    delete_stale(
      CustomField,
      team_id,
      :d4h_custom_field_id,
      MapSet.new(rows, & &1.d4h_custom_field_id)
    )

    delete_stale(
      CustomFieldBundle,
      team_id,
      :d4h_bundle_id,
      bundle_ids |> Map.keys() |> MapSet.new()
    )
  end

  @doc """
  Writes the copy from a field set's applied rows, in order (#1056): each bundle, field,
  and choice as D4H answered with it, and each deleted field. A row whose answer the
  adapter couldn't read waits for the sync.
  """
  def save_answers(team_id, rows, now) do
    Enum.each(rows, fn
      %ChangeSetRow{status: :applied, answer: %D4H.ResourceBundle{} = bundle} ->
        save_bundle(team_id, bundle, now)

      %ChangeSetRow{status: :applied, answer: %D4H.CustomField{} = field} ->
        save_field(team_id, field, now)

      %ChangeSetRow{status: :applied, answer: %{"id" => _id} = option} = row ->
        save_option(team_id, row.new_value["d4h_custom_field_id"], option)

      %ChangeSetRow{status: :applied, action: :delete_custom_field} = row ->
        delete_field(team_id, row.d4h_record_id)

      _row ->
        :ok
    end)
  end

  @doc """
  Writes one field as D4H answered a write with it (#1056), so the page that follows
  shows it before the sync. Its bundle must be in the copy already, as save_bundle/3
  puts a new one. Returns the copy, with its bundle.
  """
  def save_field(team_id, %D4H.CustomField{} = field, now) do
    bundle_id =
      field.d4h_bundle_id &&
        CustomFieldBundle
        |> where([b], b.team_id == ^team_id and b.d4h_bundle_id == ^field.d4h_bundle_id)
        |> select([b], b.id)
        |> Repo.one()

    row =
      field
      |> Map.from_struct()
      |> Map.delete(:d4h_bundle_id)
      |> Map.merge(%{team_id: team_id, bundle_id: bundle_id, inserted_at: now, updated_at: now})

    upsert(CustomField, [row], [:id, :team_id, :d4h_custom_field_id, :inserted_at], [
      :team_id,
      :d4h_custom_field_id
    ])

    CustomField
    |> preload(:bundle)
    |> Repo.get_by!(team_id: team_id, d4h_custom_field_id: field.d4h_custom_field_id)
  end

  @doc "Writes one bundle as D4H answered its create with it (#1056)."
  def save_bundle(team_id, %D4H.ResourceBundle{} = bundle, now) do
    save_bundles(team_id, [bundle], now)
    :ok
  end

  @doc """
  Puts one choice, as D4H answered a write with it, on its field's copy (#1056): a
  changed one in its place, a new one last.
  """
  def save_option(team_id, d4h_custom_field_id, %{"id" => id} = option) do
    case Repo.get_by(CustomField, team_id: team_id, d4h_custom_field_id: d4h_custom_field_id) do
      nil ->
        :ok

      field ->
        others = Enum.reject(field.options, &(&1["id"] == id))

        options =
          case Enum.find_index(field.options, &(&1["id"] == id)) do
            nil -> List.insert_at(others, -1, option)
            index -> List.insert_at(others, index, option)
          end

        field |> Ecto.Changeset.change(options: options) |> Repo.update!()
        :ok
    end
  end

  @doc "Takes a field D4H deleted out of the copy. The values on records stay."
  def delete_field(team_id, d4h_custom_field_id) do
    CustomField
    |> where([f], f.team_id == ^team_id and f.d4h_custom_field_id == ^d4h_custom_field_id)
    |> Repo.delete_all()

    :ok
  end

  # Returns the local id of each bundle, by its D4H id.
  defp save_bundles(team_id, d4h_bundles, now) do
    rows =
      d4h_bundles
      |> Enum.uniq_by(& &1.d4h_bundle_id)
      |> Enum.map(fn bundle ->
        bundle
        |> Map.from_struct()
        |> Map.merge(%{team_id: team_id, inserted_at: now, updated_at: now})
      end)

    upsert(CustomFieldBundle, rows, [:id, :team_id, :d4h_bundle_id, :inserted_at], [
      :team_id,
      :d4h_bundle_id
    ])

    d4h_ids = Enum.map(rows, & &1.d4h_bundle_id)

    CustomFieldBundle
    |> where([b], b.team_id == ^team_id and b.d4h_bundle_id in ^d4h_ids)
    |> select([b], {b.d4h_bundle_id, b.id})
    |> Repo.all()
    |> Map.new()
  end

  defp upsert(schema, rows, keep, conflict_target) do
    rows
    |> Enum.chunk_every(100)
    |> Enum.each(
      &Repo.insert_all(schema, &1,
        on_conflict: {:replace_all_except, keep},
        conflict_target: conflict_target
      )
    )
  end

  defp delete_stale(schema, team_id, d4h_id_field, synced_d4h_ids) do
    stale_ids =
      schema
      |> where([r], r.team_id == ^team_id)
      |> StaleRows.ids(d4h_id_field, synced_d4h_ids)

    if stale_ids != [] do
      {count, _} = schema |> where([r], r.id in ^stale_ids) |> Repo.delete_all()
      Logger.info("Deleted #{count} stale #{schema.__schema__(:source)} for team #{team_id}")
    end
  end
end
