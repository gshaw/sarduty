defmodule App.ViewData.TeamAttention do
  @moduledoc """
  What the team dashboard's "Needs attention" list shows (#205). Pure: the counts from
  `TeamDashboardViewData` and `now` in, items out, warnings first. An item leaves the
  list once its count is zero, so the list empties as the work gets done.
  """

  alias App.Adapter.D4H
  alias Service.Format

  @max_items 7

  @doc """
  The items to show, at most #{@max_items}. Each is a map with `key`, `level`
  (`:warning` or `:info`), `title`, `detail` (where the fix happens, or nil), and
  `action`, the text of its link. The letters and untagged items also carry the `year`; `untagged` is a list of `%{year:, count:}`. `service`
  is where the team's records live, `:d4h` or `:records` (D4H.service/1).
  """
  def items(rows, now) do
    this_year = Service.YearRange.year_in(now, rows.timezone)

    [
      refresh_item(rows.refresh, rows.service),
      drafts_item(rows.draft_count, rows.service),
      expiring_item(rows.expiring_count, rows.expiring_days, rows.service),
      missing_details_item(rows.missing_details_count, rows.service),
      not_seen_item(rows.not_seen),
      group_changes_item(rows.group_change_count),
      proposed_changes_item(rows.proposed_change_count, rows.service),
      chores_item(rows.chore_count),
      chores_to_send_item(rows.chores_to_send, rows.service),
      attendance_to_send_item(rows.attendance_to_send, rows.service)
    ]
    |> Enum.concat(Enum.map(rows.untagged, &untagged_item(&1, this_year, rows.service)))
    |> Enum.concat([letters_item(rows.letters, now, rows.timezone)])
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&(&1.level != :warning))
    |> Enum.take(@max_items)
  end

  defp refresh_item(%{state: :failed, message: message}, service) do
    %{
      key: :refresh,
      level: :warning,
      title: "SAR Duty cannot refresh from #{D4H.service_name(service)}",
      detail: message,
      action: "Open team settings"
    }
  end

  defp refresh_item(%{state: :key_rejected}, service) do
    %{
      key: :refresh,
      level: :warning,
      title: "SAR Duty cannot refresh from #{D4H.service_name(service)}",
      detail: "Your #{D4H.key_name(service)} no longer works.",
      action: "Open team settings"
    }
  end

  defp refresh_item(_ok_or_refreshing, _service), do: nil

  defp drafts_item(0, _service), do: nil

  # A team on SAR Duty Records publishes on the activity's page in SAR Duty.
  defp drafts_item(count, :records),
    do: %{
      drafts_item(count, :d4h)
      | detail:
          Format.count(count,
            one: "Check its attendance, then publish it.",
            many: "Check their attendance, then publish them."
          )
    }

  defp drafts_item(count, :d4h) do
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

  defp expiring_item(0, _days, _service), do: nil

  # A team on SAR Duty Records awards qualifications on each member's tab in SAR Duty.
  defp expiring_item(count, days, :records),
    do: %{
      expiring_item(count, days, :d4h)
      | detail: "Record renewals on each member's Qualifications tab."
    }

  defp expiring_item(count, days, :d4h) do
    %{
      key: :expiring,
      level: :warning,
      title:
        Format.count(count,
          one: "%d award expires within #{Format.days(days)}",
          many: "%d awards expire within #{Format.days(days)}"
        ),
      detail: "Record renewals in D4H.",
      action: "Show expiring awards"
    }
  end

  defp missing_details_item(0, _service), do: nil

  defp missing_details_item(count, service) do
    %{
      key: :missing_details,
      level: :info,
      title:
        Format.count(count,
          one: "%d member has no email or mobile phone",
          many: "%d members have no email or mobile phone"
        ),
      detail: missing_details_where(service),
      action: "Show members"
    }
  end

  defp not_seen_item(nil), do: nil

  # The watched group is gone from D4H. Say so rather than watch everyone (#366).
  defp not_seen_item(%{missing_group: true}) do
    %{
      key: :watch_missing,
      level: :warning,
      title: "The group you watch is no longer in D4H",
      detail: "Select another in team settings.",
      action: "Open team settings"
    }
  end

  defp not_seen_item(%{count: 0}), do: nil

  # Members drifting away, for someone to check in with (#247, #366). `params` are the
  # Members list's filters, so the link shows the members counted.
  defp not_seen_item(%{count: count, days: days, group: group, params: params}) do
    who =
      if group,
        do:
          Format.count(count,
            one: "%d member of #{group} has",
            many: "%d members of #{group} have"
          ),
        else: Format.count(count, one: "%d member has", many: "%d members have")

    %{
      key: :not_seen,
      level: :info,
      title: "#{who} not attended an activity in #{period(days)}",
      detail: Format.count(count, one: "Check in with them.", many: "Check in with each one."),
      action: "Show members",
      params: params
    }
  end

  @doc ~s(How `not_seen_days` reads in text: "90 days", or "a year".)
  def period(365), do: "a year"
  def period(days), do: Format.days(days)

  # A team on SAR Duty Records changes its members in SAR Duty.
  defp missing_details_where(:d4h), do: "Add the missing details in D4H."
  defp missing_details_where(:records), do: "Add the missing details on each member's page."

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

  defp proposed_changes_item(0, _service), do: nil

  # An AI agent's change sets wait for a team admin (#216).
  defp proposed_changes_item(count, service) do
    name = D4H.service_name(service)

    %{
      key: :proposed_changes,
      level: :info,
      title:
        Format.count(count,
          one: "%d proposed change to #{name}",
          many: "%d proposed changes to #{name}"
        ),
      detail: "An AI agent proposed them. Nothing changes in #{name} until you send them.",
      action: "Review proposed changes"
    }
  end

  defp chores_item(0), do: nil

  # Members' chores wait for a team admin to accept them (#341).
  defp chores_item(count) do
    %{
      key: :chores,
      level: :info,
      title: Format.count(count, one: "%d chore to accept", many: "%d chores to accept"),
      detail: "Members logged them. They count once you accept them.",
      action: "Review chores"
    }
  end

  defp chores_to_send_item(0, _service), do: nil

  # A team admin's decision sends chores to D4H at once (#341), so a chore activity with
  # changes to send is one whose send did not go through.
  defp chores_to_send_item(count, service) do
    name = D4H.service_name(service)

    %{
      key: :chores_to_send,
      level: :warning,
      title:
        Format.count(count,
          one: "%d chore activity out of date in #{name}",
          many: "%d chore activities out of date in #{name}"
        ),
      detail: "The last send did not go through. Send the changes again.",
      action: "Review chores"
    }
  end

  @doc """
  Attendance a team admin hasn't sent to D4H, from `TeamDashboardViewData.attendance_to_send/2`,
  oldest first. The item carries the activity to open: the only one, or the oldest.
  `service` is where the team's records live, as for `items/2`.
  """
  def attendance_to_send_item([], _service), do: nil

  def attendance_to_send_item([activity], service) do
    %{
      key: :attendance_to_send,
      level: :info,
      activity_id: activity.id,
      title: "Attendance to send: #{activity.title}",
      detail: "Review it, then send it to #{D4H.service_name(service)}.",
      action: "Send attendance"
    }
  end

  def attendance_to_send_item([oldest | _rest] = activities, service) do
    %{
      attendance_to_send_item([oldest], service)
      | title:
          "Attendance to send for #{Format.count(length(activities), one: "%d activity", many: "%d activities")}",
        detail: "The oldest is #{oldest.title}."
    }
  end

  defp untagged_item(%{count: 0}, _this_year, _service), do: nil

  # Letters count no hours for an activity with no hours tag (#323). Last year's shows only
  # in letter season, and has its own key so both can show.
  defp untagged_item(%{count: count, year: year}, this_year, service) do
    %{
      key: if(year == this_year, do: :untagged, else: :untagged_last_year),
      level: :info,
      year: year,
      title:
        Format.count(count,
          one: "%d activity in #{year} has no hours tag",
          many: "%d activities in #{year} have no hours tag"
        ),
      detail: untagged_detail(count, service),
      action: "Show activities"
    }
  end

  defp untagged_detail(count, :records),
    do:
      Format.count(count,
        one: "Tax credit letters count no hours for it. Set its hours with Change tags.",
        many: "Tax credit letters count no hours for them. Set each one's hours with Change tags."
      )

  # These are all published, and D4H refuses tags on a published activity (#358).
  defp untagged_detail(count, :d4h),
    do:
      Format.count(count,
        one: "Tax credit letters count no hours for it. Set its hours tag in D4H.",
        many: "Tax credit letters count no hours for them. Set each one's hours tag in D4H."
      )

  defp letters_item(nil, _now, _timezone), do: nil
  defp letters_item(%{count: 0}, _now, _timezone), do: nil

  defp letters_item(%{count: count, year: year}, now, timezone) do
    if Service.Period.letter_season?(now, timezone) do
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
