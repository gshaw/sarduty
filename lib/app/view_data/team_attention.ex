defmodule App.ViewData.TeamAttention do
  @moduledoc """
  What the team dashboard's "Needs attention" list shows (#205). Pure: the counts from
  `TeamDashboardViewData` and `now` in, items out, warnings first. An item leaves the
  list once its count is zero, so the list empties as the work gets done.
  """

  alias Service.Format

  @max_items 6

  # Drafts from this many days back are worth checking; older ones are left alone.
  @draft_days 30

  # Members file their taxes by April 30, so letters are worth a nudge until then.
  @letter_months 1..4

  def draft_days, do: @draft_days

  @doc "Whether `now` falls in the months the tax credit letters item can show."
  def letter_season?(now, timezone),
    do: DateTime.shift_zone!(now, timezone).month in @letter_months

  @doc """
  The items to show, at most #{@max_items}. Each is a map with `key`, `level`
  (`:warning` or `:info`), `title`, `detail`, and `action`, the text of its link. The
  letters item also carries the `year`.
  """
  def items(rows, now) do
    [
      refresh_item(rows.refresh),
      drafts_item(rows.draft_count),
      expiring_item(rows.expiring_count, rows.expiring_days),
      missing_details_item(rows.missing_details_count),
      group_changes_item(rows.group_change_count),
      letters_item(rows.letters, now, rows.timezone)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&(&1.level != :warning))
    |> Enum.take(@max_items)
  end

  defp refresh_item(%{state: :failed, message: message}) do
    %{
      key: :refresh,
      level: :warning,
      title: "SAR Duty cannot refresh from D4H",
      detail: message,
      action: "Open team settings"
    }
  end

  defp refresh_item(%{state: :key_rejected}) do
    %{
      key: :refresh,
      level: :warning,
      title: "SAR Duty cannot refresh from D4H",
      detail: "D4H rejected the team key. Save a new one in team settings.",
      action: "Open team settings"
    }
  end

  defp refresh_item(_ok_or_refreshing), do: nil

  defp drafts_item(0), do: nil

  defp drafts_item(count) do
    %{
      key: :drafts,
      level: :warning,
      title: Format.count(count, one: "%d activity to check", many: "%d activities to check"),
      detail: "Attendance can still change until the activity is published in D4H.",
      action: "Check activities"
    }
  end

  defp expiring_item(0, _days), do: nil

  defp expiring_item(count, days) do
    %{
      key: :expiring,
      level: :warning,
      title:
        Format.count(count,
          one: "%d qualification expires in #{days} days",
          many: "%d qualifications expire in #{days} days"
        ),
      detail: "Renew them in D4H, or members drop out of groups that need them.",
      action: "Review qualifications"
    }
  end

  defp missing_details_item(0), do: nil

  defp missing_details_item(count) do
    %{
      key: :missing_details,
      level: :info,
      title:
        Format.count(count, one: "%d member missing details", many: "%d members missing details"),
      detail: "ID cards need a photo, and login by text needs a mobile phone.",
      action: "Show members"
    }
  end

  defp group_changes_item(0), do: nil

  defp group_changes_item(count) do
    %{
      key: :group_changes,
      level: :info,
      title:
        Format.count(count, one: "%d group change waiting", many: "%d group changes waiting"),
      detail:
        "Group rules would add or remove members. Review the changes before they go to D4H.",
      action: "Review groups"
    }
  end

  defp letters_item(nil, _now, _timezone), do: nil
  defp letters_item(%{count: 0}, _now, _timezone), do: nil

  defp letters_item(%{count: count, year: year}, now, timezone) do
    if letter_season?(now, timezone) do
      %{
        key: :letters,
        level: :info,
        year: year,
        title:
          Format.count(count,
            one: "%d tax credit letter to create for #{year}",
            many: "%d tax credit letters to create for #{year}"
          ),
        detail: "Members with hours in #{year} need theirs before they file by April 30.",
        action: "Create letters"
      }
    end
  end
end
