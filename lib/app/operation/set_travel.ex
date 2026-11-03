defmodule App.Operation.SetTravel do
  @moduledoc """
  Sets how the checked attended rows got to an activity (#230), from its Travel page:
  drove to the ICP or the yard, at the saved round trip; a passenger, at 0 km; or km a
  team admin typed. A row with no route to where it drove is skipped, so the admin types
  its km. A published activity's travel can't change, like its attendance.

  plan/4 is pure; call/7 checks the activity, plans against the rows as saved now, and
  saves.
  """

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Trip
  alias App.ViewData.ActivityTravel
  alias Service.Format

  def call(team, %Activity{} = activity, user, ids, travel, km_text, now) do
    cond do
      activity.deleted_at -> {:error, :deleted}
      Activity.locked?(activity) -> {:error, :published}
      true -> set(team, activity, user, ids, travel, km_text, now)
    end
  end

  defp set(team, activity, user, ids, travel, km_text, now) do
    view = ActivityTravel.load(team, activity, now)

    with {:ok, plan} <- plan(view.rows, ids, travel, km_text) do
      Trip.save_all!(activity, user, plan.sets, now)
      {:ok, plan}
    end
  end

  @doc """
  Which checked rows (local attendance ids) to set, and to what: `{:ok, %{travel:,
  sets: [%{attendance:, member:, travel:, km:}], skipped: [row]}}`, where a skipped row
  has no route to where it drove. Or `{:error, reason}`: :nothing_checked, :bad_km, or
  :bad_travel. Ids the page didn't show are ignored.
  """
  def plan(rows, ids, travel, km_text) do
    ids = MapSet.new(ids)
    checked = Enum.filter(rows, &MapSet.member?(ids, &1.attendance.id))

    cond do
      travel not in Trip.travels() -> {:error, :bad_travel}
      checked == [] -> {:error, :nothing_checked}
      true -> plan_km(checked, travel, km_text)
    end
  end

  defp plan_km(checked, "other", km_text) do
    case parse_km(km_text) do
      {:ok, km} -> {:ok, result("other", Enum.map(checked, &set(&1, "other", km)), [])}
      :error -> {:error, :bad_km}
    end
  end

  defp plan_km(checked, travel, _km_text) do
    {sets, skipped} =
      Enum.reduce(checked, {[], []}, fn row, {sets, skipped} ->
        case km(row, travel) do
          nil -> {sets, [row | skipped]}
          km -> {[set(row, travel, km) | sets], skipped}
        end
      end)

    {:ok, result(travel, Enum.reverse(sets), Enum.reverse(skipped))}
  end

  defp km(_row, "passenger"), do: 0
  defp km(row, "icp"), do: row.activity_km
  defp km(row, "yard"), do: row.yard_km

  defp set(row, travel, km),
    do: %{attendance: row.attendance, member: row.member, travel: travel, km: km}

  defp result(travel, sets, skipped), do: %{travel: travel, sets: sets, skipped: skipped}

  @doc "Typed km: `{:ok, km}` for a whole number from 0, or :error."
  def parse_km(text) do
    case text |> to_string() |> String.trim() |> Integer.parse() do
      {km, ""} when km >= 0 -> {:ok, km}
      _other -> :error
    end
  end

  @doc ~s(The toast: "3 rows set to ICP." and who was skipped.)
  def result_text(%{sets: sets, skipped: skipped, travel: travel}) do
    done =
      if sets == [], do: nil, else: "#{rows_text(length(sets))} set to #{to_text(travel, sets)}."

    [done, skipped_text(skipped, travel)] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  defp to_text("icp", _sets), do: "ICP"
  defp to_text("yard", _sets), do: "yard"
  defp to_text("passenger", _sets), do: "passenger"
  defp to_text("other", [set | _]), do: Format.km(set.km)

  defp skipped_text([], _travel), do: nil

  defp skipped_text(skipped, travel) do
    names = skipped |> Enum.map(& &1.member.name) |> Enum.uniq() |> Format.and_list()
    where = if travel == "icp", do: "the ICP", else: "the yard"
    "No route from #{names}'s home to #{where}, so type their km."
  end

  defp rows_text(count), do: Format.count(count, one: "1 row", many: "%d rows")

  @doc "Why nothing was set, for the toast."
  def error_text(_team, :nothing_checked), do: "Check the rows to set first."
  def error_text(_team, :bad_km), do: "Type the km as a whole number, such as 140."
  def error_text(_team, :bad_travel), do: "Choose how they got there."

  def error_text(team, :published),
    do: "Published, so travel can't be changed. #{D4H.unpublish_text(team)}"

  def error_text(_team, :deleted), do: "This activity is deleted."
end
