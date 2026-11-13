defmodule App.Operation.SaveOwnDetails do
  @moduledoc """
  A member changes their own address, emergency contacts, and the member fields D4H lets
  them change from their page (#156, #1056). plan/3 compares the form with the member's
  copy, which the sync keeps (#423), and makes one `:update_member` row naming only what
  changed, with the old values. call/4 sends it straight to D4H as a change set of source
  `:member`, then updates the copy, so the next refresh sees nothing new.

  The fields a member may change are fields/1's, looked up through the member's team on
  every save: a field id the form sends that isn't one of them is never sent.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.CustomField
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.SaveCustomFields
  alias App.Repo

  @fields %{
    "address" => :address,
    "primary_emergency_contact" => :primary_emergency_contact,
    "secondary_emergency_contact" => :secondary_emergency_contact
  }

  @doc """
  The member fields `member` changes on their own page, in order: the ones D4H sets to
  `editable`, when the team's key can fill in fields. None otherwise.
  """
  def fields(%Member{team: %Team{} = team}) do
    if Team.d4h_can?(team, :field_values),
      do:
        team.id |> CustomField.member_fields(:self) |> Enum.filter(&CustomField.member_changes?/1),
      else: []
  end

  @doc """
  `{:ok, :unchanged}`, `{:ok, member}` after D4H took the change, or `{:error, text}`.
  `values` are the details by key, and under "fields" the form's member fields by D4H
  field id.
  """
  def call(%Member{} = member, %User{} = user, values, now) do
    case plan(member, values, fields(member)) do
      :unchanged -> {:ok, :unchanged}
      fields -> apply_row(member, user, row(member, fields), now)
    end
  end

  @doc """
  What changed between the member's copy and the form's `values`, as
  `%{old_value: …, new_value: …}`, or `:unchanged`. A contact goes whole when any of
  its fields changed. Blank values are nil. Only `custom_fields`, the ones the member may
  change, are read from `values["fields"]`, and only the ones that changed go, as
  `custom_values`.
  """
  def plan(%Member{} = member, values, custom_fields \\ []) do
    {old, new} =
      member
      |> details_changes(values)
      |> add_field_changes(member, custom_fields, values["fields"] || %{})

    if new == %{},
      do: :unchanged,
      else: %{old_value: Map.take(old, Map.keys(new)), new_value: new}
  end

  defp details_changes(member, values) do
    old = %{
      "address" => member.address,
      "primary_emergency_contact" =>
        member.primary_emergency_contact || D4H.Member.empty_contact(),
      "secondary_emergency_contact" =>
        member.secondary_emergency_contact || D4H.Member.empty_contact()
    }

    new =
      values
      |> Map.take(Map.keys(@fields))
      |> blank_to_nil()
      |> Map.reject(fn {key, value} -> old[key] == value end)

    {old, new}
  end

  defp add_field_changes({old, new}, member, custom_fields, params) do
    case SaveCustomFields.changes(member, custom_fields, params) do
      :unchanged ->
        {old, new}

      {old_values, new_values} ->
        {Map.put(old, "custom_values", old_values), Map.put(new, "custom_values", new_values)}
    end
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

  # D4H doesn't change a member's updatedAt for custom fields, so the copy takes the
  # values sent, as Change fields does.
  defp update_copy(member, new_value) do
    {sent, details} = Map.pop(new_value, "custom_values")
    changes = Map.new(details, fn {key, value} -> {Map.fetch!(@fields, key), value} end)

    changes =
      if sent,
        do: Map.put(changes, :custom_values, merge_values(member.custom_values, sent)),
        else: changes

    member |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  defp merge_values(current, sent) do
    (current || %{})
    |> Map.merge(sent)
    |> Map.reject(fn {_id, value} -> value == nil end)
  end
end
