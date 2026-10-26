defmodule App.Operation.SaveTitledRecord do
  @moduledoc """
  A team admin adds, renames, or deletes a qualification of a team on SAR Duty Records
  (docs/records.md), or a group of any team (#546). Both are only a title. Each change is
  one change set row applied through App.Operation.ApplyEdit. A deleted qualification
  takes its awards with it, and a deleted group its members and its own rules.

  A group's local copy is written here from the service's answer, as group rules do, and
  the next sync confirms it. Two groups can't share a title in any case, counting the
  organization's, and the organization's groups are never renamed or deleted: that might
  change them for every team in it.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Operation.RefreshD4HData.UpsertGroups
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
    form = %TitleFormViewModel{title: record && record.title}

    with :ok <- check_owner(team, record),
         {:ok, %{title: title}} <- validate(team, kind, record, form, params) do
      if record != nil and record.title == title,
        do: {:ok, record},
        else: apply_title(team, kind, record, title, user, now)
    end
  end

  @doc "The form's changeset, refusing a title another group of the team uses."
  def changeset(%Team{} = team, kind, record, form, params) do
    %{max_length: max_length} = Map.fetch!(@kinds, kind)
    changeset = TitleFormViewModel.changeset(form, params, max_length)
    title = Ecto.Changeset.get_field(changeset, :title)

    if kind == :group and title != nil and title_taken?(team, record, title),
      do: Ecto.Changeset.add_error(changeset, :title, "Enter a title no other group uses."),
      else: changeset
  end

  defp validate(team, kind, record, form, params),
    do: team |> changeset(kind, record, form, params) |> Ecto.Changeset.apply_action(:insert)

  defp title_taken?(team, record, title) do
    title = String.downcase(title)

    Group
    |> where([g], g.team_id == ^team.id)
    |> select([g], {g.id, g.title})
    |> Repo.all()
    |> Enum.any?(fn {id, other} ->
      id != (record && record.id) and String.downcase(other) == title
    end)
  end

  defp check_owner(team, %Group{organization_owned: true}),
    do:
      {:error,
       "Only #{Team.organization_name(team) || "your organization"} can rename or delete it."}

  defp check_owner(_team, _record), do: :ok

  defp apply_title(team, kind, record, title, user, now) do
    with {:ok, id} <-
           ApplyEdit.call(team, user, plan(kind, record, title), now, opts(kind, record)) do
      {:ok, save_local(team, kind, record, id, title)}
    end
  end

  # The sync after the edit copied the qualification.
  defp save_local(team, :qualification, _record, id, _title),
    do: Repo.get_by(Qualification, team_id: team.id, d4h_qualification_id: id)

  defp save_local(team, :group, nil, id, title) do
    params = %{team_id: team.id, d4h_group_id: id, title: title}

    case Group.get_by(team_id: team.id, d4h_group_id: id) do
      nil -> Group.insert!(params)
      group -> Group.update!(group, params)
    end
  end

  defp save_local(_team, :group, group, _id, title), do: Group.update!(group, %{title: title})

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

    with :ok <- check_owner(team, record),
         {:ok, _id} <- ApplyEdit.call(team, user, row, now, opts(kind, nil)) do
      delete_local(record)
    end
  end

  # Its own rules go with it. Rules of other groups that name it break until changed.
  defp delete_local(%Group{} = group) do
    Repo.transaction(fn ->
      GroupRule
      |> where([r], r.team_id == ^group.team_id and r.d4h_group_id == ^group.d4h_group_id)
      |> Repo.delete_all()

      UpsertGroups.delete([group.id])
    end)

    :ok
  end

  defp delete_local(_qualification), do: :ok

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
