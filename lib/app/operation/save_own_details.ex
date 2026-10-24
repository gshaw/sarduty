defmodule App.Operation.SaveOwnDetails do
  @moduledoc """
  A member changes their own address and emergency contacts from their page (#156).
  plan/2 compares the form with the member's copy, which the sync keeps (#423), and
  makes one `:update_member` row naming only what changed, with the old values. call/4
  sends it straight to D4H as a change set of source `:member`, then updates the copy,
  so the next refresh sees nothing new.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Operation.ApplyChangeSet
  alias App.Repo

  @fields %{
    "address" => :address,
    "primary_emergency_contact" => :primary_emergency_contact,
    "secondary_emergency_contact" => :secondary_emergency_contact
  }

  @doc "`{:ok, :unchanged}`, `{:ok, member}` after D4H took the change, or `{:error, text}`."
  def call(%Member{} = member, %User{} = user, values, now) do
    case plan(member, Map.take(values, Map.keys(@fields))) do
      :unchanged -> {:ok, :unchanged}
      fields -> apply_row(member, user, row(member, fields), now)
    end
  end

  @doc """
  What changed between the member's copy and the form's `values`, as
  `%{old_value: …, new_value: …}`, or `:unchanged`. A contact goes whole when any of
  its fields changed. Blank values are nil.
  """
  def plan(%Member{} = member, values) do
    old = %{
      "address" => member.address,
      "primary_emergency_contact" =>
        member.primary_emergency_contact || D4H.Member.empty_contact(),
      "secondary_emergency_contact" =>
        member.secondary_emergency_contact || D4H.Member.empty_contact()
    }

    new = values |> blank_to_nil() |> Map.reject(fn {key, value} -> old[key] == value end)

    if new == %{},
      do: :unchanged,
      else: %{old_value: Map.take(old, Map.keys(new)), new_value: new}
  end

  defp blank_to_nil(%{} = map),
    do: Map.new(map, fn {key, value} -> {key, blank_to_nil(value)} end)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp row(member, fields) do
    %ChangeSetRow{
      action: :update_member,
      member_id: member.id,
      d4h_record_id: member.d4h_member_id,
      old_value: fields.old_value,
      new_value: fields.new_value
    }
  end

  defp apply_row(member, user, row, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{team_id: member.team_id, source: :member, proposed_by_user_id: user.id},
        [row]
      )

    case ApplyChangeSet.call(member.team, change_set, user, now) do
      {:ok, [%ChangeSetRow{status: :applied}]} ->
        {:ok, update_copy(member, row.new_value)}

      {:ok, [%ChangeSetRow{error: error}]} ->
        {:error, error}

      {:error, _reason} ->
        {:error, "The change did not go through. Try again."}
    end
  end

  defp update_copy(member, new_value) do
    changes = Map.new(new_value, fn {key, value} -> {Map.fetch!(@fields, key), value} end)
    member |> Ecto.Changeset.change(changes) |> Repo.update!()
  end
end
