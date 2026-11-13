defmodule App.Operation.ChangeCustomField do
  @moduledoc """
  A team admin changes one of the team's own custom fields (#1056 step 4): its
  settings and its choices, or archives and restores it. Its kind and type never change,
  as D4H's PATCH takes neither, and a choice is archived, never deleted.

  One change set, source `:edit`, through App.Operation.ApplyEdit: a new bundle first
  when the form names one, then the field's row with only what changed, then a row for
  each choice added or changed. The copy takes what D4H answers with.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.ChangeSetRow
  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle
  alias App.Model.Team
  alias App.Operation.CreateCustomField
  alias App.ViewModel.CustomFieldFormViewModel

  @doc """
  Changes `field` from Change field's `params`. `{:ok, field}` with the copy,
  `{:error, changeset}` for the form, or `{:error, text}`.
  """
  def call(%Team{} = team, %User{} = user, %CustomField{} = field, params, now) do
    field = App.Repo.preload(field, :bundle)
    fields = CustomField.get_all_with_archived(team.id)

    with :ok <- check(team, field),
         {:ok, form} <-
           field
           |> CustomFieldFormViewModel.from_field()
           |> CustomFieldFormViewModel.changeset(params, fields, field)
           |> Ecto.Changeset.apply_action(:update),
         {:ok, _rows} <-
           send(team, user, plan(field, form, CustomFieldBundle.get_all(team.id)), now) do
      {:ok, CustomField.get_for_team!(team.id, field.id)}
    end
  end

  @doc "Archives `field`, keeping every answer, or restores it. `:ok` or `{:error, text}`."
  def set_archived(%Team{} = team, %User{} = user, %CustomField{} = field, archived?, now)
      when is_boolean(archived?) do
    with :ok <- check(team, field),
         {:ok, _rows} <- send(team, user, [archive_row(field, archived?)], now),
         do: :ok
  end

  @doc "The row that archives or restores `field`."
  def archive_row(%CustomField{} = field, archived?) do
    %ChangeSetRow{
      action: :update_custom_field,
      d4h_record_id: field.d4h_custom_field_id,
      old_value: %{"archived" => not is_nil(field.archived_at)},
      new_value: %{"archived" => archived?}
    }
  end

  @doc """
  The rows that change `field` to `form`, in order: a new bundle's, the field's with
  only the settings that changed, then each choice added or changed. Restricted never
  changes on a member or equipment field. A choice id the field doesn't have is
  ignored, never sent.
  """
  def plan(%CustomField{} = field, %CustomFieldFormViewModel{} = form, bundles) do
    {bundle_row, bundle_value} = CreateCustomField.bundle_plan(form, bundles)
    field_row = field_row(field, form, bundle_row, bundle_value)
    Enum.reject([bundle_row, field_row], &is_nil/1) ++ choice_rows(field, form)
  end

  # The field's row, or nil when no setting changed and no new bundle waits for it.
  defp field_row(field, form, bundle_row, bundle_value) do
    old = old_value(field)
    {d4h_bundle_id, created} = Map.split(bundle_value, ["d4h_bundle_id"])

    changed =
      form
      |> CustomFieldFormViewModel.value()
      |> Map.merge(d4h_bundle_id)
      |> Map.take(keys(field))
      |> Map.reject(fn {key, value} -> old[key] == value end)

    if changed != %{} or bundle_row do
      %ChangeSetRow{
        action: :update_custom_field,
        d4h_record_id: field.d4h_custom_field_id,
        old_value: Map.take(old, ["d4h_bundle_id" | Map.keys(changed)]),
        new_value: Map.merge(changed, created)
      }
    end
  end

  # What a field's kind and type let change.
  defp keys(%CustomField{target: target, field_type: type}) do
    ~w(title hint d4h_bundle_id) ++
      if(type == "number", do: ["value_units"], else: []) ++
      if(CustomField.activity_target?(target), do: ["required"], else: []) ++
      if(CustomField.restricted_matters?(target), do: ["restricted"], else: []) ++
      if(target == "member", do: ["member_privacy"], else: [])
  end

  defp old_value(%CustomField{} = field) do
    %{
      "title" => field.title,
      "hint" => field.hint,
      "value_units" => field.value_units,
      "required" => field.required,
      "restricted" => field.restricted,
      "member_privacy" => field.member_privacy,
      "d4h_bundle_id" => field.bundle && field.bundle.d4h_bundle_id
    }
  end

  defp choice_rows(%CustomField{} = field, %CustomFieldFormViewModel{choices: choices}) do
    options = Map.new(field.options, &{&1["id"], &1})

    choices
    |> Enum.with_index()
    |> Enum.flat_map(fn {choice, ordering} ->
      choice_row(field, options, choice, ordering)
    end)
  end

  # A new choice, archived before it was ever sent, is left out.
  defp choice_row(_field, _options, %{"id" => nil, "archived" => true}, _ordering), do: []

  defp choice_row(field, _options, %{"id" => nil} = choice, ordering) do
    [
      %ChangeSetRow{
        action: :create_custom_field_option,
        old_value: %{},
        new_value: %{
          "d4h_custom_field_id" => field.d4h_custom_field_id,
          "label" => choice["label"],
          "ordering" => ordering
        }
      }
    ]
  end

  defp choice_row(field, options, %{"id" => id} = choice, ordering) do
    case options[id] do
      nil ->
        []

      option ->
        old = %{
          "label" => option["label"],
          "ordering" => option["ordering"],
          "archived" => option["archived"]
        }

        new = %{
          "label" => choice["label"],
          "ordering" => ordering,
          "archived" => choice["archived"]
        }

        changed = Map.reject(new, fn {key, value} -> old[key] == value end)

        if changed == %{},
          do: [],
          else: [
            %ChangeSetRow{
              action: :update_custom_field_option,
              d4h_record_id: id,
              old_value: Map.take(old, Map.keys(changed)),
              new_value: Map.put(changed, "d4h_custom_field_id", field.d4h_custom_field_id)
            }
          ]
    end
  end

  defp send(_team, _user, [], _now), do: {:ok, []}
  defp send(team, user, rows, now), do: CreateCustomField.send_rows(team, user, rows, now)

  @doc """
  Whether a team admin can change `field`, or the text to show. Delete asks it too
  (App.Operation.DeleteCustomField).
  """
  def check(%Team{} = team, %CustomField{team_id: team_id} = field) when team_id == team.id do
    cond do
      CustomField.team_changes?(team, field) -> :ok
      CustomField.organisation?(field) -> {:error, "Only the organization can change its fields."}
      field.frozen -> {:error, "#{D4H.service_name(team)} locks this field. It cannot change."}
      true -> CreateCustomField.check_team(team)
    end
  end
end
