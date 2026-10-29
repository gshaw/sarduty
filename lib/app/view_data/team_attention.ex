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
  The items to show, at most `limit`: #{@max_items} for the page, or `:all` for an agent
  (#595). Each is a map with `key`, `level`
  (`:danger`, `:warning`, or `:info`, sorted in that order), `title`, `detail` (where the fix happens, or nil), and
  `action`, the text of its link. The letters and untagged items also carry the `year`; `untagged` is a list of `%{year:, count:}`. `service`
  is where the team's records live, `:d4h` or `:records` (D4H.service/1).
  """
  def items(rows, now, limit \\ @max_items) do
    this_year = Service.YearRange.year_in(now, rows.timezone)

    [
      refresh_item(rows.refresh, rows.service),
      drafts_item(rows.draft_count, rows.service),
      missing_fields_item(rows.missing_fields_count, rows.service),
      expiring_item(rows.expiring_count, rows.expiring_days, rows.service),
      missing_details_item(rows.missing_details_count, rows.service),
      not_seen_item(rows.not_seen),
      group_changes_item(rows.group_change_count),
      certificates_item(rows.certificate_count),
      chores_item(rows.chore_count),
      chores_to_send_item(rows.chores_to_send),
      attendance_to_send_item(rows.attendance_to_send),
      no_shows_item(rows.no_shows)
    ]
    |> Enum.concat(retiring_items(rows))
    |> Enum.concat(untagged_items(rows, this_year))
    |> Enum.concat([letters_item(rows.letters, now, rows.timezone)])
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&level_order/1)
    |> take(limit)
  end

  # Stable, so items keep their order within a level.
  defp level_order(%{level: :danger}), do: 0
  defp level_order(%{level: :warning}), do: 1
  defp level_order(%{level: :info}), do: 2

  defp untagged_items(rows, this_year),
    do: Enum.map(rows.untagged, &untagged_item(&1, this_year, rows.service))

  defp take(items, :all), do: items
  defp take(items, limit), do: Enum.take(items, limit)

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

  defp drafts_item(count, service) do
    name = D4H.service_name(service)

    %{
      key: :drafts,
      level: :warning,
      title: Format.count(count, one: "%d draft activity", many: "%d draft activities"),
      detail:
        Format.count(count,
          one: "Check its attendance, then publish it in #{name}.",
          many: "Check their attendance, then publish them in #{name}."
        ),
      action: "Show drafts"
    }
  end

  defp missing_fields_item(0, _service), do: nil

  defp missing_fields_item(count, service) do
    %{
      key: :missing_fields,
      level: :warning,
      title:
        Format.count(count,
          one: "%d draft activity is missing required fields",
          many: "%d draft activities are missing required fields"
        ),
      detail:
        Format.count(count,
          one: "#{D4H.service_name(service)} won't publish it until they're filled in.",
          many: "#{D4H.service_name(service)} won't publish them until they're filled in."
        ),
      action: "Show activities"
    }
  end

  defp expiring_item(0, _days, _service), do: nil

  # A team on SAR Duty Records awards qualifications on each member's tab in SAR Duty.
  defp expiring_item(count, days, :records),
    do: %{
      expiring_item(count, days, :d4h)
      | detail: "Record renewals on each member's Qualifications tab."
    }

  defp expiring_item(count, days, service) do
    %{
      key: :expiring,
      level: :warning,
      title:
        Format.count(count,
          one: "%d award expires within #{Format.days(days)}",
          many: "%d awards expire within #{Format.days(days)}"
        ),
      detail: "Record renewals in #{D4H.service_name(service)}.",
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
          one: "%d member has no email, mobile phone, or address",
          many: "%d members have no email, mobile phone, or address"
        ),
      detail: missing_details_where(service),
      action: "Show members"
    }
  end

  defp not_seen_item(nil), do: nil

  # The watched group was deleted. Say so rather than watch everyone (#366).
  defp not_seen_item(%{missing_group: true}) do
    %{
      key: :watch_missing,
      level: :warning,
      title: "The group you watch was deleted",
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

  # Retiring members (#514). The line for those who hold nothing says what comes next, so
  # nobody stays Retiring for good.
  defp retiring_items(%{retiring: retiring, service: service}),
    do: [
      retiring_missing_item(retiring),
      retiring_access_item(retiring, service),
      retiring_holding_item(retiring),
      retiring_clear_item(retiring, service)
    ]

  defp retiring_missing_item(%{missing_group: true}) do
    %{
      key: :retiring_missing,
      level: :warning,
      title: "The Retiring group was deleted",
      detail: "Select another in team settings.",
      action: "Open team settings"
    }
  end

  defp retiring_missing_item(_none_or_counts), do: nil

  # SAR Duty shuts a retiring member out of itself, but only a team admin can in D4H.
  # Danger, the one red item, first in the list: until then they still reach everything
  # D4H shows them.
  defp retiring_access_item(%{d4h_access: count}, service) when count > 0 do
    name = D4H.service_name(service)

    %{
      key: :retiring_access,
      level: :danger,
      title:
        Format.count(count,
          one: "%d retiring member can still log in to #{name}",
          many: "%d retiring members can still log in to #{name}"
        ),
      detail: no_access(service),
      action: "Show members"
    }
  end

  defp retiring_access_item(_none_or_missing, _service), do: nil

  @doc ~s{Where a team admin takes a retiring member's access away: "Set their access to No access in D4H."}
  def no_access(:records), do: "Set their access to No access on their Change member page."
  def no_access(service), do: "Set their access to No access in #{D4H.service_name(service)}."

  defp retiring_holding_item(%{holding: count, items: items}) when count > 0 do
    who = Format.count(count, one: "%d retiring member holds", many: "%d retiring members hold")

    %{
      key: :retiring,
      level: :info,
      title: "#{who} #{Format.count(items, one: "%d item", many: "%d items")}",
      detail: nil,
      action: "Show items"
    }
  end

  defp retiring_holding_item(_none_or_missing), do: nil

  defp retiring_clear_item(%{clear: count}, service) when count > 0 do
    %{
      key: :retiring_clear,
      level: :info,
      title:
        Format.count(count,
          one: "%d retiring member holds no items",
          many: "%d retiring members hold no items"
        ),
      detail: retire_them(service),
      action: "Show members"
    }
  end

  defp retiring_clear_item(_none_or_missing, _service), do: nil

  @doc ~s{What to do with a retiring member who holds nothing: "Retire them in D4H." On a Records team, members retire on their Change member page in SAR Duty.}
  def retire_them(:records), do: "Retire them."
  def retire_them(service), do: "Retire them in #{D4H.service_name(service)}."

  @doc ~s(How `not_seen_days` reads in text: "90 days", or "a year".)
  def period(365), do: "a year"
  def period(days), do: Format.days(days)

  # A team on SAR Duty Records changes its members in SAR Duty.
  defp missing_details_where(:records), do: "Add the missing details on each member's page."

  defp missing_details_where(service),
    do: "Add the missing details in #{D4H.service_name(service)}."

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

  defp certificates_item(0), do: nil

  # Members' certificates wait for a team admin to accept them (#493).
  defp certificates_item(count) do
    %{
      key: :certificates,
      level: :info,
      title:
        Format.count(count, one: "%d certificate to accept", many: "%d certificates to accept"),
      detail: "Look at each one, then accept or decline it.",
      action: "Review certificates"
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

  defp chores_to_send_item(0), do: nil

  # A team admin's decision sends chores to D4H at once (#341), so a chore activity with
  # changes to send is one whose send did not go through.
  defp chores_to_send_item(count) do
    %{
      key: :chores_to_send,
      level: :warning,
      title:
        Format.count(count,
          one: "%d chore activity out of date",
          many: "%d chore activities out of date"
        ),
      detail: "The last send did not go through. Send the changes again.",
      action: "Review chores"
    }
  end

  @doc """
  Attendance a team admin hasn't sent, from `TeamDashboardViewData.attendance_to_send/2`,
  oldest first. The item carries the activity to open: the only one, or the oldest.
  """
  def attendance_to_send_item([]), do: nil

  def attendance_to_send_item([activity]) do
    %{
      key: :attendance_to_send,
      level: :info,
      activity_id: activity.id,
      title: "Attendance to send: #{activity.title}",
      detail: "Review the changes, then send them.",
      action: "Send attendance"
    }
  end

  def attendance_to_send_item([oldest | _rest] = activities) do
    %{
      attendance_to_send_item([oldest])
      | title:
          "Attendance to send for #{Format.count(length(activities), one: "%d activity", many: "%d activities")}",
        detail: "The oldest is #{oldest.title}."
    }
  end

  @doc """
  No-shows nobody has followed up, from activities that started in the last week (#650),
  from `NoShow.to_follow_up/3`, oldest first. The item opens the only activity, or the
  oldest.
  """
  def no_shows_item([]), do: nil

  def no_shows_item([activity]) do
    %{
      key: :no_shows,
      level: :info,
      activity_id: activity.id,
      title: "#{no_shows_count(activity.count)} to follow up: #{activity.title}",
      detail: "Check each one is OK, then mark them followed up.",
      action: "Follow up"
    }
  end

  def no_shows_item([oldest | _rest] = activities) do
    total = activities |> Enum.map(& &1.count) |> Enum.sum()
    from = activities |> length() |> Format.count(one: "%d activity", many: "%d activities")

    %{
      no_shows_item([oldest])
      | title: "#{no_shows_count(total)} to follow up from #{from}",
        detail: "The oldest is #{oldest.title}."
    }
  end

  defp no_shows_count(count), do: Format.count(count, one: "%d no-show", many: "%d no-shows")

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
  defp untagged_detail(count, service) do
    name = D4H.service_name(service)

    Format.count(count,
      one: "Tax credit letters count no hours for it. Set its hours tag in #{name}.",
      many: "Tax credit letters count no hours for them. Set each one's hours tag in #{name}."
    )
  end

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
            one: "%d tax credit letter to send for #{year}",
            many: "%d tax credit letters to send for #{year}"
          ),
        detail: "Members file by April 30.",
        action: "Send letters"
      }
    end
  end
end
