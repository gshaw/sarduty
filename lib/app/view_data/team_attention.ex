defmodule App.ViewData.TeamAttention do
  @moduledoc """
  What the team dashboard's "Needs attention" list shows (#205). Pure: the counts from
  `TeamDashboardViewData` and `now` in, items out, warnings first. An item leaves the
  list once its count is zero, so the list empties as the work gets done.
  """

  alias Service.Format

  @max_items 7

  # Members file their taxes by April 30, so letters are worth a nudge until then.
  @letter_months 1..4

  @doc "Whether `now` falls in the months the tax credit letters item can show."
  def letter_season?(now, timezone),
    do: DateTime.shift_zone!(now, timezone).month in @letter_months

  @doc """
  The items to show, at most #{@max_items}. Each is a map with `key`, `level`
  (`:warning` or `:info`), `title`, `detail` (where the fix happens, or nil), and
  `action`, the text of its link. The letters item also carries the `year`.
  """
  def items(rows, now) do
    [
      refresh_item(rows.refresh),
      drafts_item(rows.draft_count),
      expiring_item(rows.expiring_count, rows.expiring_days),
      missing_details_item(rows.missing_details_count),
      group_changes_item(rows.group_change_count),
      proposed_changes_item(rows.proposed_change_count),
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
      detail: "Your D4H access key no longer works.",
      action: "Open team settings"
    }
  end

  defp refresh_item(_ok_or_refreshing), do: nil

  defp drafts_item(0), do: nil

  defp drafts_item(count) do
    %{
      key: :drafts,
      level: :warning,
      title: Format.count(count, one: "%d draft activity", many: "%d draft activities"),
      detail:
        Format.count(count,
          one: "Check its attendance, then publish it in D4H.",
          many: "Check their attendance, then publish them in D4H."
        ),
      action: "Show drafts"
    }
  end

  defp expiring_item(0, _days), do: nil

  defp expiring_item(count, days) do
    %{
      key: :expiring,
      level: :warning,
      title:
        Format.count(count,
          one: "%d qualification expires within #{days} days",
          many: "%d qualifications expire within #{days} days"
        ),
      detail: "Record renewals in D4H.",
      action: "Show qualifications"
    }
  end

  defp missing_details_item(0), do: nil

  defp missing_details_item(count) do
    %{
      key: :missing_details,
      level: :info,
      title:
        Format.count(count,
          one: "%d member has no email or mobile phone",
          many: "%d members have no email or mobile phone"
        ),
      detail: "Add the missing details in D4H.",
      action: "Show members"
    }
  end

  defp group_changes_item(0), do: nil

  # The changes go to D4H only from the review page, so no detail is needed.
  defp group_changes_item(count) do
    %{
      key: :group_changes,
      level: :info,
      title:
        Format.count(count,
          one: "%d change from group rules",
          many: "%d changes from group rules"
        ),
      detail: nil,
      action: "Review changes"
    }
  end

  defp proposed_changes_item(0), do: nil

  # An AI agent's change sets wait for a team admin (#216).
  defp proposed_changes_item(count) do
    %{
      key: :proposed_changes,
      level: :info,
      title:
        Format.count(count,
          one: "%d proposed change to D4H",
          many: "%d proposed changes to D4H"
        ),
      detail: "An AI agent proposed them. Nothing changes in D4H until you send them.",
      action: "Review proposed changes"
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
        detail: "Members file by April 30.",
        action: "Create letters"
      }
    end
  end
end
