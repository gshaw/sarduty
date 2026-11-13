defmodule App.Operation.CreateCustomField do
  @moduledoc """
  A team admin adds one of the team's own custom fields (#1056 step 4), on D4H or SAR
  Duty Records. The one way a field is made: the Fields tab's Add field and #875's
  import templates both call it.

  One change set, source `:edit`, through App.Operation.ApplyEdit: a new bundle first
  when the form names one the team doesn't have, then the field in it. The copy takes
  what D4H answers with, so the page that follows shows the field before the sync.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.ChangeSetRow
  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Operation.RefreshD4HData.UpsertCustomFields
  alias App.Repo
  alias App.ViewModel.CustomFieldFormViewModel

  @doc """
  Adds a field from `params`, as Add field's form posts them, or with `choices` as a
  list of labels. `{:ok, field}` with the copy, nil when D4H's answer couldn't be read
  and the sync will copy it; `{:error, changeset}` for the form; or `{:error, text}`.
  """
  def call(%Team{} = team, %User{} = user, params, now) do
    fields = CustomField.get_all_with_archived(team.id)
    bundles = CustomFieldBundle.get_all(team.id)
    target = params["target"] || params[:target]

    with :ok <- check_team(team),
         {:ok, form} <-
           target
           |> CustomFieldFormViewModel.new()
           |> CustomFieldFormViewModel.changeset(params, fields)
           |> Ecto.Changeset.apply_action(:insert),
         {:ok, rows} <- send_rows(team, user, plan(form, fields, bundles), now) do
      {:ok, find_field(team, rows)}
    end
  end

  @doc """
  The rows that add `form`'s field: a bundle's first when it names a new one. A new field
  goes after the team's others of its kind. Only live choices are sent.
  """
  def plan(%CustomFieldFormViewModel{} = form, fields, bundles) do
    {bundle_row, bundle_value} = bundle_plan(form, bundles)

    new_value =
      form
      |> CustomFieldFormViewModel.value()
      |> Map.merge(%{
        "target" => form.target,
        "field_type" => form.field_type,
        "ordering" => next_ordering(fields, form.target)
      })
      |> Map.merge(bundle_value)
      |> put_options(form)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    field_row = %ChangeSetRow{action: :create_custom_field, old_value: %{}, new_value: new_value}
    Enum.reject([bundle_row, field_row], &is_nil/1)
  end

  defp put_options(value, %CustomFieldFormViewModel{field_type: type, choices: choices})
       when type in ~w(single_choice multiple_choice),
       do: Map.put(value, "options", for(c <- choices, not c["archived"], do: c["label"]))

  defp put_options(value, _form), do: value

  defp next_ordering(fields, target) do
    fields
    |> Enum.filter(&(&1.owner_type == "Team" and &1.target == target))
    |> Enum.map(&(&1.ordering + 1))
    |> Enum.max(fn -> 0 end)
  end

  @doc """
  What the form's bundle adds to a field's row: `{bundle_row, value}`. A new name is a
  `create_resource_bundle` row to send first, and the field's row waits for its id
  (`created_in_set`). A bundle the team has is its id, and none is nil, with no row.
  """
  def bundle_plan(%CustomFieldFormViewModel{} = form, bundles) do
    case CustomFieldFormViewModel.bundle(form, bundles) do
      nil ->
        {nil, %{"d4h_bundle_id" => nil}}

      {:existing, bundle} ->
        {nil, %{"d4h_bundle_id" => bundle.d4h_bundle_id}}

      {:new, title} ->
        row = %ChangeSetRow{
          action: :create_resource_bundle,
          old_value: %{},
          new_value: %{
            "target" => form.target,
            "title" => title,
            "ordering" => CustomFieldBundle.next_ordering(bundles, form.target)
          }
        }

        {row, %{"d4h_bundle_id" => nil, "created_in_set" => true}}
    end
  end

  @doc """
  Sends a field set's rows and writes the copy from what applied. `{:ok, rows}`, or
  `{:error, text}` with the first refusal, after the copy takes the rows that went.
  """
  def send_rows(%Team{} = team, %User{} = user, rows, now) do
    with {:ok, rows} <- ApplyEdit.call_rows(team, user, rows, now) do
      UpsertCustomFields.save_answers(team.id, rows, now)

      case Enum.find(rows, &(&1.status != :applied)) do
        nil -> {:ok, rows}
        row -> {:error, row.error}
      end
    end
  end

  @doc "Whether the team's key can change fields, or the text to show when it cannot."
  def check_team(%Team{} = team) do
    if Team.d4h_can?(team, :custom_fields),
      do: :ok,
      else: {:error, "This #{D4H.key_name(team)} cannot change fields. Use an Owner's key."}
  end

  defp find_field(team, rows) do
    case Enum.find(rows, &(&1.action == :create_custom_field)) do
      %ChangeSetRow{answer: %D4H.CustomField{d4h_custom_field_id: d4h_id}} ->
        CustomField
        |> Repo.get_by!(team_id: team.id, d4h_custom_field_id: d4h_id)
        |> Repo.preload(:bundle)

      _row ->
        nil
    end
  end
end
