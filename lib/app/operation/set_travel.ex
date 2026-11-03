defmodule App.Operation.SetTravel do
  @moduledoc """
  Sets how the checked attended rows got to an activity (#230), from its Travel page:
  drove to the ICP or the yard, at the saved round trip; a passenger, at 0 km; or km a
  team admin typed. A row with no route to where it drove is skipped, so the admin types
  its km. Clear takes a row's trip away, back to not set. A published activity's travel can't change, like its attendance.

  plan/4 is pure; call/7 checks the activity, plans against the rows as saved now, and
  saves.
  """

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Member
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

    # A team admin's own rows count as checked: they set them.
    own = user && Member.find_by_email(team, user.email, now)

    with {:ok, plan} <- plan(view.rows, ids, travel, km_text) do
      Trip.save_all!(activity, user, plan.sets, now, own && own.id)
      Trip.delete_all!(activity, Enum.map(plan.cleared, & &1.attendance.d4h_attendance_id))
      {:ok, plan}
    end
  end

  @doc """
  Which checked rows (local attendance ids) to set, and to what: `{:ok, %{travel:,
  sets: [%{attendance:, member:, travel:, km:}], skipped: [row], cleared: [row]}}`,
  where a skipped row has no route to where it drove. "clear" fills `cleared` with the
  checked rows that have a trip. Or `{:error, reason}`: :nothing_checked, :bad_km, or
  :bad_travel. Ids the page didn't show are ignored.
  """
  def plan(rows, ids, travel, km_text) do
    ids = MapSet.new(ids)
    checked = Enum.filter(rows, &MapSet.member?(ids, &1.attendance.id))

    cond do
      travel not in ["clear" | Trip.travels()] -> {:error, :bad_travel}
      checked == [] -> {:error, :nothing_checked}
      travel == "clear" -> plan_clear(checked)
      true -> plan_km(checked, travel, km_text)
    end
  end

  defp plan_clear(checked) do
    case Enum.filter(checked, & &1[:trip]) do
      [] -> {:error, :nothing_checked}
      cleared -> {:ok, %{result("clear", [], []) | cleared: cleared}}
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

  defp result(travel, sets, skipped),
    do: %{travel: travel, sets: sets, skipped: skipped, cleared: []}

  @doc "Typed km: `{:ok, km}` for a whole number from 0, or :error."
  def parse_km(text) do
    case text |> to_string() |> String.trim() |> Integer.parse() do
      {km, ""} when km >= 0 -> {:ok, km}
      _other -> :error
    end
  end

  @doc ~s(The toast: "3 rows set to ICP." and who was skipped, or "2 rows cleared.")
  def result_text(%{travel: "clear", cleared: cleared}),
    do: "#{rows_text(length(cleared))} cleared."

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
