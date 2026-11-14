defmodule App.Operation.ReorderCustomFields do
  @moduledoc """
  A team admin puts the team's own live fields of one kind in a new order (#1056 step
  4), from Change order. D4H keeps it in each field's `ordering`, so it is one change
  set with an `update_custom_field` row for each field that moved, through
  App.Operation.ApplyEdit. The copy takes what D4H answers with.

  Where the team's fields sit among its organization's on a record stays the fallback
  in docs/custom-fields.md.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Operation.CreateCustomField

  @doc """
  `ids` are the local ids of the team's own live fields of `target`, in their new order,
  from the browser. `:ok`, or `{:error, text}`.
  """
  def call(%Team{} = team, %User{} = user, target, ids, now) do
    fields = fields(team, target)

    with :ok <- CreateCustomField.check_team(team),
         {:ok, rows} <- plan(fields, ids),
         {:ok, _rows} <- send(team, user, rows, now),
         do: :ok
  end

  @doc "The fields Change order lists: the team's own live ones of `target`, in order."
  def fields(%Team{} = team, target) do
    team.id
    |> CustomField.get_all(target)
    |> Enum.filter(&CustomField.team_changes?(team, &1))
  end

  @doc """
  The rows that put `fields` in the order of `ids`, numbered from 0, for the fields
  whose `ordering` changes. `ids` must name each field once, or
  `{:error, text}`: the list changed since the page opened.
  """
  def plan(fields, ids) do
    by_id = Map.new(fields, &{to_string(&1.id), &1})
    ids = Enum.map(ids, &to_string/1)

    if Enum.sort(ids) == by_id |> Map.keys() |> Enum.sort() do
      rows =
        for {id, ordering} <- Enum.with_index(ids),
            field = by_id[id],
            field.ordering != ordering do
          %ChangeSetRow{
            action: :update_custom_field,
            d4h_record_id: field.d4h_custom_field_id,
            old_value: %{"ordering" => field.ordering},
            new_value: %{"ordering" => ordering}
          }
        end

      {:ok, rows}
    else
      {:error, "The fields changed since the page opened. Open it again."}
    end
  end

  defp send(_team, _user, [], _now), do: {:ok, []}
  defp send(team, user, rows, now), do: CreateCustomField.send_rows(team, user, rows, now)
end
