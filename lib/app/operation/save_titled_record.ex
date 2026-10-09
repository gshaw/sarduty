defmodule App.Operation.SaveTitledRecord do
  @moduledoc """
  A team admin adds, renames, or deletes a qualification or group of a team on SAR
  Duty Records (docs/records.md). Both are only a title. Each change is one change set row applied
  through App.Operation.ApplyEdit. A deleted qualification takes its awards with it, and
  a deleted group its members.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Group
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Repo
  alias App.ViewModel.TitleFormViewModel

  @kinds %{
    qualification: %{
      schema: Qualification,
      d4h_id: :d4h_qualification_id,
      max_length: 200,
      actions: %{
        create: :create_qualification,
        update: :update_qualification,
        delete: :delete_qualification
      }
    },
    group: %{
      schema: Group,
      d4h_id: :d4h_group_id,
      max_length: 50,
      actions: %{create: :create_group, update: :update_group, delete: :delete_group}
    }
  }

  @doc """
  Adds (`record` nil) or renames a record of `kind`, `:qualification` or `:group`.
  `{:ok, record}`, `{:error, changeset}` for the form, or `{:error, text}`.
  """
  def save(%Team{} = team, kind, record, params, %User{} = user, now) do
    %{max_length: max_length} = Map.fetch!(@kinds, kind)
    form = %TitleFormViewModel{title: record && record.title}

    case TitleFormViewModel.validate(form, params, max_length) do
      {:ok, %{title: title}} when record != nil and record.title == title -> {:ok, record}
      {:ok, %{title: title}} -> apply_title(team, kind, record, title, user, now)
      error -> error
    end
  end

  defp apply_title(team, kind, record, title, user, now) do
    %{schema: schema, d4h_id: d4h_id} = Map.fetch!(@kinds, kind)

    with {:ok, id} <-
           ApplyEdit.call(team, user, plan(kind, record, title), now, opts(kind, record)) do
      {:ok, Repo.get_by(schema, [{:team_id, team.id}, {d4h_id, id}])}
    end
  end

  @doc "Deletes a record of `kind`. `:ok` or `{:error, text}`."
  def delete(%Team{} = team, kind, record, %User{} = user, now) do
    %{schema: schema, d4h_id: d4h_id, actions: actions} = Map.fetch!(@kinds, kind)
    ^schema = record.__struct__
    true = record.team_id == team.id

    row = %ChangeSetRow{
      action: actions.delete,
      d4h_record_id: Map.fetch!(record, d4h_id),
      old_value: %{"title" => record.title},
      new_value: %{}
    }

    with {:ok, _id} <- ApplyEdit.call(team, user, row, now, opts(kind, nil)), do: :ok
  end

  def plan(kind, nil, title) do
    %{actions: actions} = Map.fetch!(@kinds, kind)
    %ChangeSetRow{action: actions.create, old_value: %{}, new_value: %{"title" => title}}
  end

  def plan(kind, record, title) do
    %{d4h_id: d4h_id, actions: actions} = Map.fetch!(@kinds, kind)

    %ChangeSetRow{
      action: actions.update,
      d4h_record_id: Map.fetch!(record, d4h_id),
      old_value: %{"title" => record.title},
      new_value: %{"title" => title}
    }
  end

  # A group's set names the group, so its page can find it.
  defp opts(:group, %Group{id: id}), do: [group_id: id]
  defp opts(_kind, _record), do: []
end
