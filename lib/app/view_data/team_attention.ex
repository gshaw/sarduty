defmodule App.ViewData.TeamAttention do
  @moduledoc """
  What the team dashboard's "Needs attention" list shows (#205). Pure: the rows from
  `TeamDashboardViewData` and `now` in, items out, warnings first. An item leaves the
  list once its count is zero, so the list empties as the work gets done.

  An item can be snoozed (#751) when it waits on people outside SAR Duty and can sit for
  weeks: members replying, renewing, or returning gear. It carries `ids`, the local ids
  of what it counts (members, activities, or awards), and a line in `@back_sooner`. An
  item never is when it means something is broken (refresh, D4H access, a deleted
  group), when the fix is one step in SAR Duty (accept, send, review), when it leaves
  on its own (no-shows), or when it has a deadline (letters, last year's hours tags).
  `docs/needs-attention.md` has the steps for a new item.
  """

  alias App.Adapter.D4H
  alias App.Model.Team
  alias Service.Format

  @max_items 7

  @doc """
  The items as `%{shown: items, more: items, snoozed: items}`. Shown are at most
  `limit`: #{@max_items} for the page, or `:all` for an agent (#595). `more` are the rest,
  in order, which the page shows once asked ("+2 more"). Each is a map with `key`,
  `level` (`:danger`, `:warning`, or `:info`, sorted in that order), `title`, `detail`
  (where the fix happens, or nil), and `action`, the text of its link. The letters,
  untagged, and two hours tags items also carry the `year`; `untagged` is a list of
  `%{year:, count:, ids:}`, and `two_hours_tags` of `%{year:, primary:, secondary:, ids:}`.
  `service` is where the team's records live, `:d4h` or `:records` (D4H.service/1).

  An item with `ids`, what it counts, can be snoozed (#751). It is snoozed while
  one of `snoozes` (`AttentionSnooze`) has its key, has not ended, and holds every one of
  its ids, so anyone new brings it back. Snoozed items carry their `snooze` and free
  their place in the shown ones.
  """
  def items(rows, now, snoozes \\ [], limit \\ @max_items) do
    snoozes = Map.new(snoozes, &{&1.key, &1})

    {snoozed, shown} =
      rows
      |> all_items(now)
      |> Enum.map(&with_snooze(&1, snoozes[Atom.to_string(&1.key)], now))
      |> Enum.split_with(&Map.has_key?(&1, :snooze))

    {shown, more} = take(shown, limit)
    %{shown: shown, more: more, snoozed: snoozed}
  end

  defp all_items(rows, now) do
    this_year = Service.YearRange.year_in(now, rows.timezone)

    rows
    |> count_items()
    |> Enum.concat(retiring_items(rows))
    |> Enum.concat(untagged_items(rows, this_year))
    |> Enum.concat(two_hours_tags_items(rows, this_year))
    |> Enum.concat([letters_item(rows.letters, now, rows.timezone)])
    |> Enum.concat(name_items(rows.names))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&level_order/1)
  end

  defp with_snooze(item, snooze, now) do
    if snoozed?(item, snooze, now), do: Map.put(item, :snooze, snooze), else: item
  end

  defp snoozed?(%{ids: ids}, %{until: until, ids: saved}, now),
    do: DateTime.before?(now, until) and ids |> MapSet.new() |> MapSet.subset?(MapSet.new(saved))

  defp snoozed?(_item, _no_snooze, _now), do: false

  @doc "Whether a team admin can snooze the item: only one with the ids behind it."
  def can_snooze?(item), do: Map.has_key?(item, :ids)

  # What brings each item that can be snoozed back early. An item that carries `ids` needs a line
  # here; the tests check every one does.
  @back_sooner %{
    drafts: "another activity finishes as a draft",
    missing_fields: "another draft is missing required fields",
    expiring: "another award is about to expire",
    missing_details: "another member is missing details",
    not_seen: "another member stops attending",
    retiring: "another retiring member holds items",
    retiring_clear: "another retiring member holds no items",
    untagged: "another activity has no hours tag",
    two_hours_tags: "another activity has two hours tags"
  }

  @doc "When a snoozed item comes back before its time, for the dialog that snoozes it."
  def back_sooner(%{key: key}), do: "It comes back sooner if #{Map.fetch!(@back_sooner, key)}."

  defp count_items(rows) do
    [
      refresh_item(rows.refresh, rows.service),
      drafts_item(rows.draft_ids, rows.service),
      missing_fields_item(rows.missing_fields_ids, rows.service),
      expiring_item(rows.expiring_ids, rows.expiring_days, rows.service),
      missing_details_item(rows.missing_details_ids, rows.service),
      not_seen_item(rows.not_seen),
      group_changes_item(rows.group_change_count),
      certificates_item(rows.certificate_count),
      chores_item(rows.chore_count),
      chores_to_send_item(rows.chores_to_send),
      attendance_to_send_item(rows.attendance_to_send),
      no_shows_item(rows.no_shows)
    ]
  end

  # Stable, so items keep their order within a level.
  defp level_order(%{level: :danger}), do: 0
  defp level_order(%{level: :warning}), do: 1
  defp level_order(%{level: :info}), do: 2

  defp untagged_items(rows, this_year),
    do: Enum.map(rows.untagged, &untagged_item(&1, this_year, rows.service))

  defp two_hours_tags_items(rows, this_year),
    do: Enum.map(rows.two_hours_tags, &two_hours_tags_item(&1, this_year, rows.service))

  defp take(items, :all), do: {items, []}
  defp take(items, limit), do: Enum.split(items, limit)

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

  defp drafts_item([], _service), do: nil

  # A team on SAR Duty Records publishes on the activity's page in SAR Duty.
  defp drafts_item(ids, :records),
    do: %{
      drafts_item(ids, :d4h)
      | detail:
          ids
          |> length()
          |> Format.count(
            one: "Check its attendance, then publish it.",
            many: "Check their attendance, then publish them."
          )
    }

  defp drafts_item(ids, service) do
    name = D4H.service_name(service)
    count = length(ids)

    %{
      key: :drafts,
      level: :warning,
      ids: ids,
      title: Format.count(count, one: "%d draft activity", many: "%d draft activities"),
      detail:
        Format.count(count,
          one: "Check its attendance, then publish it in #{name}.",
          many: "Check their attendance, then publish them in #{name}."
        ),
      action: "Show drafts"
    }
  end

  defp missing_fields_item([], _service), do: nil

  defp missing_fields_item(ids, service) do
    count = length(ids)

    %{
      key: :missing_fields,
      level: :warning,
      ids: ids,
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

  defp expiring_item([], _days, _service), do: nil

  # A team on SAR Duty Records awards qualifications on each member's tab in SAR Duty.
  defp expiring_item(ids, days, :records),
    do: %{
      expiring_item(ids, days, :d4h)
      | detail: "Record renewals on each member's Qualifications tab."
    }

  defp expiring_item(ids, days, service) do
    count = length(ids)

    %{
      key: :expiring,
      level: :warning,
      ids: ids,
      title:
        Format.count(count,
          one: "%d award expires within #{Format.days(days)}",
          many: "%d awards expire within #{Format.days(days)}"
        ),
      detail: "Record renewals in #{D4H.service_name(service)}.",
      action: "Show expiring awards"
    }
  end

  defp missing_details_item([], _service), do: nil

  defp missing_details_item(ids, service) do
    count = length(ids)

    %{
      key: :missing_details,
      level: :info,
      ids: ids,
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

  defp not_seen_item(%{ids: []}), do: nil

  # Members drifting away, for someone to check in with (#247, #366). `params` are the
  # Members list's filters, so the link shows the members counted.
  defp not_seen_item(%{ids: ids, days: days, group: group, params: params}) do
    count = length(ids)

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
      ids: ids,
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

  defp retiring_holding_item(%{holding: count, items: items, holding_ids: ids}) when count > 0 do
    who = Format.count(count, one: "%d retiring member holds", many: "%d retiring members hold")

    %{
      key: :retiring,
      level: :info,
      ids: ids,
      title: "#{who} #{Format.count(items, one: "%d item", many: "%d items")}",
      detail: nil,
      action: "Show items"
    }
  end

  defp retiring_holding_item(_none_or_missing), do: nil

  defp retiring_clear_item(%{clear_ids: [_ | _] = ids}, service) do
    count = length(ids)

    %{
      key: :retiring_clear,
      level: :info,
      ids: ids,
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
  defp untagged_item(%{count: count, year: year} = row, this_year, service) do
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
    |> with_ids(year == this_year, row.ids)
  end

  # Last year's waits on letter season's deadline, so only this year's can be snoozed.
  defp with_ids(item, true, ids), do: Map.put(item, :ids, ids)
  defp with_ids(item, false, _ids), do: item

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

  defp two_hours_tags_item(%{primary: 0, secondary: 0}, _this_year, _service), do: nil

  # Letters count primary over secondary, and either over the other tag, without a word
  # (#763). Like the untagged item, last year's shows only in letter season.
  defp two_hours_tags_item(%{year: year} = row, this_year, service) do
    count = row.primary + row.secondary

    %{
      key: if(year == this_year, do: :two_hours_tags, else: :two_hours_tags_last_year),
      level: :info,
      year: year,
      title:
        Format.count(count,
          one: "%d activity in #{year} has two hours tags",
          many: "%d activities in #{year} have two hours tags"
        ),
      detail: "#{counted_as(row)} #{two_hours_tags_fix(count, service)}",
      action: "Show activities"
    }
    |> with_ids(year == this_year, row.ids)
  end

  defp counted_as(%{primary: primary, secondary: secondary}) do
    case {primary, secondary} do
      {1, 0} ->
        "Tax credit letters count primary hours for it."

      {0, 1} ->
        "Tax credit letters count secondary hours for it."

      {_, 0} ->
        "Tax credit letters count primary hours for them."

      {0, _} ->
        "Tax credit letters count secondary hours for them."

      _ ->
        "Tax credit letters count primary hours for #{Format.number(primary)} " <>
          "and secondary hours for #{Format.number(secondary)}."
    end
  end

  defp two_hours_tags_fix(count, :records),
    do:
      Format.count(count,
        one: "Take the extra tag off with Change tags.",
        many: "Take each extra tag off with Change tags."
      )

  # A published activity is locked (#358), so its tags change in D4H.
  defp two_hours_tags_fix(count, service) do
    name = D4H.service_name(service)

    Format.count(count,
      one: "Take the extra tag off with Change tags, or in #{name} if it is published.",
      many: "Take each extra tag off with Change tags, or in #{name} for a published one."
    )
  end

  # The team's names start as one, so these nudge until the short ones are short (#738).
  # By length only: SAR Duty can't tell a right legal name from a wrong one.
  defp name_items(names), do: [long_name_item(names), long_abbreviated_name_item(names)]

  defp long_name_item(names) do
    if Team.name_too_long?(names, :name) do
      %{
        key: :long_name,
        level: :info,
        title: "Your team's name is too long for ID cards",
        detail:
          "\"#{names.name}\" is cut off on ID cards and the phone top bar. " <>
            "A name of #{Format.characters(Team.name_advice(:name))} or fewer fits.",
        action: "Open team settings"
      }
    end
  end

  defp long_abbreviated_name_item(names) do
    if Team.name_too_long?(names, :abbreviated_name) do
      %{
        key: :long_abbreviated_name,
        level: :info,
        title: "Your team's abbreviated name is too long for texts",
        detail:
          "Texts to members start with it. " <>
            "#{Format.characters(Team.name_advice(:abbreviated_name))} or fewer leaves room for the message.",
        action: "Open team settings"
      }
    end
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
