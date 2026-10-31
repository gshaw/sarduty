defmodule App.Operation.SaveWhiteboardNote do
  @moduledoc """
  A team admin's post, change, archive, or delete of a whiteboard note (#515): a change
  set of one row, source `:whiteboard`, applied at once. Then the local copy is written
  from what was sent, so the page shows the change straight away; the sync's next head
  check reads it back.

  Each returns `{:ok, note}` (the deleted note for a delete), or `{:error, text}` to
  show the person.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Team
  alias App.Model.WhiteboardNote
  alias App.Operation.ApplyChangeSet
  alias App.Repo
  alias App.ViewModel.WhiteboardNoteFormViewModel

  @doc """
  When a note whose last day is `day` archives: the start of the next day in the team's
  time zone, in UTC.
  """
  def archived_at(%Date{} = day, timezone) do
    day
    |> Date.add(1)
    |> DateTime.new!(~T[00:00:00], timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  @doc "The row's fields for a form's values, as the change set stores them."
  def note_value(%WhiteboardNoteFormViewModel{} = form, timezone) do
    %{
      "text" => form.text,
      "url" => form.url,
      "important" => form.important,
      "archived_at" => form.until |> archived_at(timezone) |> ApplyChangeSet.iso()
    }
  end

  @doc "A note's fields as a change set stores them, for `old_value`."
  def note_value(%WhiteboardNote{} = note) do
    %{
      "text" => note.text,
      "url" => note.url,
      "important" => note.important,
      "archived_at" => ApplyChangeSet.iso(note.archived_at)
    }
  end

  def post(
        %Team{} = team,
        %User{} = user,
        %WhiteboardNoteFormViewModel{} = form,
        now \\ DateTime.utc_now()
      ) do
    new_value = note_value(form, team.timezone)
    row = %ChangeSetRow{action: :create_whiteboard_note, new_value: new_value}

    with {:ok, d4h_id} <- apply_row(team, user, row, now) do
      %WhiteboardNote{
        team_id: team.id,
        d4h_whiteboard_note_id: d4h_id,
        owner_kind: :team,
        d4h_created_at: DateTime.truncate(now, :second)
      }
      |> put_value(new_value)
      |> Repo.insert(
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: [:team_id, :d4h_whiteboard_note_id]
      )
    end
  end

  def change(
        %Team{} = team,
        %User{} = user,
        %WhiteboardNote{} = note,
        %WhiteboardNoteFormViewModel{} = form,
        now \\ DateTime.utc_now()
      ) do
    update(team, user, note, note_value(form, team.timezone), now)
  end

  @doc "Takes the note off the whiteboard now. It stays under Archived."
  def archive(%Team{} = team, %User{} = user, %WhiteboardNote{} = note, now \\ DateTime.utc_now()) do
    update(
      team,
      user,
      note,
      %{"archived_at" => now |> DateTime.truncate(:second) |> ApplyChangeSet.iso()},
      now
    )
  end

  def delete(team, user, note, now \\ DateTime.utc_now())

  def delete(%Team{} = team, %User{} = user, %WhiteboardNote{} = note, now)
      when note.team_id == team.id and note.owner_kind == :team do
    row = %ChangeSetRow{
      action: :delete_whiteboard_note,
      d4h_record_id: note.d4h_whiteboard_note_id,
      old_value: note_value(note),
      new_value: %{}
    }

    with {:ok, _d4h_id} <- apply_row(team, user, row, now), do: Repo.delete(note)
  end

  def delete(_team, _user, %WhiteboardNote{}, _now), do: {:error, read_only()}

  # A team note only: an organization's note is read-only to its teams.
  defp update(team, user, note, new_value, now)
       when note.team_id == team.id and note.owner_kind == :team do
    row = %ChangeSetRow{
      action: :update_whiteboard_note,
      d4h_record_id: note.d4h_whiteboard_note_id,
      old_value: note_value(note),
      new_value: new_value
    }

    with {:ok, _d4h_id} <- apply_row(team, user, row, now) do
      note |> put_value(new_value) |> Repo.update()
    end
  end

  defp update(_team, _user, _note, _new_value, _now), do: {:error, read_only()}

  defp apply_row(team, user, row, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{team_id: team.id, source: :whiteboard, proposed_by_user_id: user.id},
        [row]
      )

    case ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, [%ChangeSetRow{status: :applied, d4h_record_id: d4h_id}]} -> {:ok, d4h_id}
      {:ok, [%ChangeSetRow{error: error}]} -> {:error, refused_text(team, error)}
      {:error, :no_team_key} -> {:error, "This team has no key. Ask a SAR Duty site admin."}
      {:error, error} -> {:error, D4H.error_text(team, error)}
    end
  end

  defp read_only, do: "Only the team's own notes can change."

  @doc """
  What to show when the service did not take the note. ApplyChangeSet keeps a refusal's
  title, and words a service that did not answer itself.
  """
  def refused_text(team, error) do
    service = D4H.service_name(team)
    title = String.trim_trailing(error || "", ".")

    cond do
      String.starts_with?(title, "#{service} did not answer") -> error
      D4H.records?(team) -> "#{service} did not take the note: #{title}."
      true -> "#{service} did not take the note: #{title}. Try again."
    end
  end

  # A changeset of what the row sent, for the local copy.
  defp put_value(note, value) do
    changes =
      for {key, field} <- [
            {"text", :text},
            {"url", :url},
            {"important", :important},
            {"archived_at", :archived_at}
          ],
          Map.has_key?(value, key),
          into: %{},
          do: {field, local(field, value[key])}

    Ecto.Changeset.change(note, changes)
  end

  defp local(:archived_at, nil), do: nil

  defp local(:archived_at, iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    DateTime.truncate(at, :second)
  end

  defp local(_field, value), do: value
end
