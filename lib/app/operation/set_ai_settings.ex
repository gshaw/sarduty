defmodule App.Operation.SetAISettings do
  @moduledoc """
  Saves AI writing's settings from Adminland › AI writing: who gets it, the model, and
  the monthly budget. Only a SAR Duty admin. Each save is an `ai_settings_changed`
  event with what it changed.
  """

  alias App.Accounts.User
  alias App.Model.AISettings
  alias App.Model.Event
  alias App.Repo

  @doc """
  `attrs` takes `access`, `model`, and `monthly_budget` in whole dollars. `{:ok,
  settings}`, `{:error, changeset}`, or `{:error, :not_allowed}`.
  """
  def call(attrs, %User{is_admin: true} = user) do
    settings = AISettings.get()

    changeset =
      settings
      |> AISettings.changeset(budget_in_cents(attrs))
      |> Ecto.Changeset.put_change(:updated_by_id, user.id)

    Repo.transaction(fn ->
      case Repo.insert_or_update(changeset) do
        {:ok, saved} ->
          Event.record!(:ai_settings_changed, user_id: user.id, data: changes(changeset))
          saved

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def call(_attrs, %User{}), do: {:error, :not_allowed}

  defp budget_in_cents(attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    case (attrs["monthly_budget"] || "") |> to_string() |> Integer.parse() do
      {dollars, ""} -> Map.put(attrs, "monthly_budget_cents", dollars * 100)
      _not_whole -> Map.put(attrs, "monthly_budget_cents", nil)
    end
  end

  defp changes(changeset),
    do: changeset.changes |> Map.delete(:updated_by_id) |> Map.new(fn {k, v} -> {k, v} end)
end
