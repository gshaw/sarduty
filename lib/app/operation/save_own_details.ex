defmodule App.Operation.SaveOwnDetails do
  @moduledoc """
  A member changes their own address and emergency contacts from their page (#156).
  load/1 reads what D4H holds now; SAR Duty keeps no copy of emergency contacts. plan/2
  makes one `:update_member` row naming only what changed, with D4H's old values. call/5
  sends it straight to D4H as a change set of source `:member`, then updates the copy's
  address, so the next refresh sees nothing new.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Adapter.D4H.MemberDetails
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Operation.ApplyChangeSet
  alias App.Repo

  @doc "`{:ok, %MemberDetails{}}`, or `{:error, text}` when D4H can't be read."
  def load(%Member{team: team} = member) do
    case team
         |> D4H.build_context_from_team()
         |> D4H.fetch_member_details(member.d4h_member_id) do
      {:ok, details} ->
        {:ok, details}

      {:error, _error} ->
        {:error, "SAR Duty cannot reach #{D4H.service_name(team)}. Try again later."}
    end
  end

  @doc "`{:ok, :unchanged}`, `{:ok, member}` after D4H took the change, or `{:error, text}`."
  def call(%Member{} = member, %User{} = user, %MemberDetails{} = details, values, now) do
    case plan(details, Map.take(values, fields(member.team))) do
      :unchanged -> {:ok, :unchanged}
      fields -> apply_row(member, user, row(member, fields), now)
    end
  end

  @doc """
  The fields a member changes on their team. SAR Duty Records has no emergency contacts.
  """
  def fields(team) do
    if D4H.records?(team),
      do: ["address"],
      else: ["address", "primary_emergency_contact", "secondary_emergency_contact"]
  end

  @doc """
  What changed between D4H's `details` and the form's `values`, as
  `%{old_value: …, new_value: …}`, or `:unchanged`. A contact goes whole when any of
  its fields changed. Blank values are nil.
  """
  def plan(%MemberDetails{} = details, values) do
    old = %{
      "address" => details.address,
      "primary_emergency_contact" =>
        details.primary_emergency_contact || MemberDetails.empty_contact(),
      "secondary_emergency_contact" =>
        details.secondary_emergency_contact || MemberDetails.empty_contact()
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
        {:error, "#{D4H.service_name(member.team)} did not take the change. Try again."}
    end
  end

  defp update_copy(member, %{"address" => address}),
    do: member |> Ecto.Changeset.change(address: address) |> Repo.update!()

  defp update_copy(member, _new_value), do: member
end
