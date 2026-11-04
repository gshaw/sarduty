defmodule App.Operation.SetTravel do
  @moduledoc """
  Sets how the checked attended rows got to an activity (#230), from its Travel page:
  drove to the ICP or the yard, at the saved round trip; a passenger, at 0 km; or km a
  team admin typed. A row with no route to where it drove stays as it was. A row that
  has that travel and km already isn't saved again, so its member's confirm stands. Clear
  takes a row's trip away, back to not set. A published activity's travel can't change,
  like its attendance.

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

    # A team admin's own rows count as confirmed: they set them.
    own = user && Member.find_by_email(team, user.email, now)

    with {:ok, plan} <- plan(view.rows, ids, travel, km_text) do
      Trip.save_all!(activity, user, plan.sets, now, own && own.id)
      Trip.delete_all!(activity, Enum.map(plan.cleared, & &1.attendance.d4h_attendance_id))
      {:ok, plan}
    end
  end

  @doc """
  Which checked rows (local attendance ids) to set, and to what: `{:ok, %{travel:, sets:
  [%{attendance:, member:, travel:, km:}], skipped: [row], unchanged: [row], cleared:
  [row]}}`. A skipped row has no route to where it drove. An unchanged row has that
  travel and km already, or that travel and no route to work its km out again. "clear"
  fills `cleared` with the checked rows that have a trip, and `unchanged` with the rest.
  A row without a `trip` key, such as a member's own from CheckTravel, is never
  unchanged. Or `{:error, reason}`: :nothing_checked, :bad_km, or :bad_travel. Ids the
  page didn't show are ignored.
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
    {cleared, unchanged} = Enum.split_with(checked, & &1[:trip])
    {:ok, %{result("clear") | cleared: cleared, unchanged: unchanged}}
  end

  defp plan_km(checked, "other", km_text) do
    case parse_km(km_text) do
      {:ok, km} -> {:ok, sort(checked, "other", fn _row -> km end)}
      :error -> {:error, :bad_km}
    end
  end

  defp plan_km(checked, travel, _km_text), do: {:ok, sort(checked, travel, &km(&1, travel))}

  # Each checked row into sets, skipped, or unchanged, in the order checked.
  defp sort(checked, travel, km_of) do
    plan =
      Enum.reduce(checked, result(travel), fn row, plan ->
        case fate(row, travel, km_of.(row)) do
          :unchanged -> %{plan | unchanged: [row | plan.unchanged]}
          :skipped -> %{plan | skipped: [row | plan.skipped]}
          {:set, km} -> %{plan | sets: [set(row, travel, km) | plan.sets]}
        end
      end)

    %{
      plan
      | sets: Enum.reverse(plan.sets),
        skipped: Enum.reverse(plan.skipped),
        unchanged: Enum.reverse(plan.unchanged)
    }
  end

  # The same travel at the same km, or with no route to work it out again, keeps its trip.
  defp fate(%{trip: %{travel: travel, km: saved}}, travel, km) when is_nil(km) or km == saved,
    do: :unchanged

  defp fate(_row, _travel, nil), do: :skipped
  defp fate(_row, _travel, km), do: {:set, km}

  defp km(_row, "passenger"), do: 0
  defp km(row, "icp"), do: row.activity_km
  defp km(row, "yard"), do: row.yard_km

  defp set(row, travel, km),
    do: %{attendance: row.attendance, member: row.member, travel: travel, km: km}

  defp result(travel), do: %{travel: travel, sets: [], skipped: [], unchanged: [], cleared: []}

  @doc "Typed km: `{:ok, km}` for a whole number from 0, or :error."
  def parse_km(text) do
    case text |> to_string() |> String.trim() |> Integer.parse() do
      {km, ""} when km >= 0 -> {:ok, km}
      _other -> :error
    end
  end

  @doc """
  The toast, by member, naming one: "Saved Ann Smith's travel." or "Saved 3 members'
  travel.", then who had no route; "Cleared 2 members' travel."; "Nothing changed." when
  each has it already; or, when nothing was set for want of a route, who, as an error.
  ok?/1 says which kind. A member with two rows counts once.
  """
  def result_text(%{sets: [], skipped: [], cleared: []}), do: "Nothing changed."
  def result_text(%{travel: "clear", cleared: cleared}), do: "Cleared #{whose(cleared)} travel."

  def result_text(%{sets: [], skipped: skipped, travel: travel}),
    do: "No route to #{where(travel)} for #{names(skipped)}. Change their rows and choose Other."

  def result_text(%{sets: sets, skipped: [], travel: _travel}), do: "Saved #{whose(sets)} travel."

  def result_text(%{sets: sets, skipped: skipped, travel: travel}),
    do:
      "Saved #{whose(sets)} travel. No route to #{where(travel)} for #{names(skipped)}, so nothing changed for them."

  @doc "Whether the toast is a result, not an error: false when only no route stopped it."
  def ok?(%{sets: [], skipped: [_ | _]}), do: false
  def ok?(_plan), do: true

  # "Ann Smith's" or "3 members'".
  defp whose(rows) do
    case Enum.uniq_by(rows, & &1.member.id) do
      [row] -> "#{row.member.name}'s"
      members -> "#{length(members)} members'"
    end
  end

  defp names(rows), do: rows |> Enum.map(& &1.member.name) |> Enum.uniq() |> Format.and_list()

  defp where("icp"), do: "the ICP"
  defp where("yard"), do: "the yard"

  @doc "Why nothing was set, for the toast."
  def error_text(_team, :nothing_checked), do: "Check the rows to set first."
  def error_text(_team, :bad_km), do: "Type the km as a whole number, such as 140."
  def error_text(_team, :bad_travel), do: "Choose how they got there."

  def error_text(team, :published),
    do: "Published, so travel cannot be changed. #{D4H.unpublish_text(team)}"

  def error_text(_team, :deleted), do: "This activity is deleted."
end
