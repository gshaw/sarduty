defmodule Web.ActivityMembersLive.Action do
  @moduledoc """
  One change on an activity's Members tab (#766): a team admin checks members in the
  table, picks a change from one list, and presses one button. Web.ActivityMembersLive
  lists every change in its `@actions`, in the list's order; each is a module with this
  behaviour.

  A change applies in place, through an operation, and the tables update on the tab
  (`run/1` answers `{:in_place, change}`). Or it opens a step (`{:step, live_action}`):
  the module is then a LiveComponent too, drawn in the tab's place on a `live_action`
  route of the same LiveView, such as `/members/ask`, so the ticks never leave the
  page. See Web.ActivityMembersLive for the step's rules. A step gets `team`, `activity`,
  `user`, `checked`, `standings`, `counts` (the panel's), `service`, and `back`, the
  tab's path, and draws everything under the page's title.

  `ctx` is `%{activity:, team:, now:, retiring:}`, with the team's retiring member ids.
  `checked` are the checked members' rows, one per member as the tab shows them (App.ViewData.ActivityMembers), each with its `member`,
  `status`, and `duration_in_minutes`.

  The list follows writing.md's Choices for checked rows (#920): a label that starts with
  a verb, a hint that says what happens to the checked, with counts, and a choice that
  reaches nobody checked greyed with the reason.
  """

  alias Web.Components.Messages

  @type ctx :: %{activity: map(), team: map(), now: DateTime.t(), retiring: MapSet.t()}

  @doc ~s(The list's value, also in ids: "absent".)
  @callback value() :: String.t()

  @doc ~s(The list's label: "Mark absent".)
  @callback label() :: String.t()

  @doc """
  The line under the label: what happens to the `checked`, with counts, and who it skips
  or what they lose. With nothing checked, the same sentence without counts. Pure.
  """
  @callback hint(ctx(), checked :: [map()]) :: String.t()

  @doc """
  Nil, or why the choice reaches nobody checked, shown greyed in its hint's place:
  "Everyone checked has replied." Nil with nothing checked. Pure.
  """
  @callback unavailable(ctx(), checked :: [map()]) :: String.t() | nil

  @doc "Whether the list offers it now."
  @callback offered?(ctx()) :: boolean()

  @doc "How many of the checked members it changes, for the button."
  @callback count(ctx(), checked :: [map()]) :: non_neg_integer()

  @doc ~s(The button for `count` members: "Mark 3 absent".)
  @callback button_text(count :: non_neg_integer()) :: String.t()

  @doc "The button's variant: red for a change that takes something away."
  @callback variant() :: :primary | :danger

  @doc "The button's `data-confirm` attributes, or `%{}` when it doesn't ask."
  @callback confirm(ctx(), checked :: [map()]) :: map()

  @doc """
  Whether it applies in place, as the operation's change, or opens a step, for the
  checked members.
  """
  @callback run(checked :: [map()]) :: {:in_place, atom()} | {:step, atom()}

  @doc """
  The choice the list shows picked: `choice`, an action's value, while it reaches someone
  checked. Before the start, when it greys out, the next one offered after it that
  doesn't, then the first; with no choice, the first that reaches someone. From the start
  a greyed choice leaves nothing picked, since the next one could be Mark absent, which
  takes hours away: the admin picks again. Pure.
  """
  def pick(actions, choice, ctx, checked, before_start?) do
    open = Enum.reject(actions, & &1.unavailable(ctx, checked))
    index = Enum.find_index(actions, &(&1.value() == choice))

    cond do
      !before_start? ->
        if index && Enum.at(actions, index) in open, do: Enum.at(actions, index)

      index == nil ->
        List.first(open)

      true ->
        actions
        |> Enum.split(index)
        |> then(fn {before, from} -> from ++ before end)
        |> Enum.find(&(&1 in open))
    end
  end

  @doc ~s(The checked as a sentence's subject: "All 3 checked", or "The 1 checked".)
  def all_checked(1), do: "The 1 checked"
  def all_checked(count), do: "All #{count} checked"

  @doc ~s(A count and its verb: "1 has", "2 have", from the two verbs.)
  def count_verb(1, one, _many), do: "1 #{one}"
  def count_verb(count, _one, many), do: "#{count} #{many}"

  @doc """
  The confirm's line on the hours the checked who attended lose, or nil when nobody
  checked attended. Mark attended gives back the activity's times, not a member's own,
  so a change that takes them says so. Up to 3 by name (Messages.name_them?/1): "Avery
  Chen's 4h 30m and Jordan Lee's 5 hours go." More, a count and the total: "6 who
  attended lose 30 hours." The checked rows behind the dialog show who
  (/styles/confirm-dialog#many). `too` adds "too", for a change that takes more than the
  hours.
  """
  def hours_lost(checked, too \\ false) do
    attended = for row <- checked, row.status == "attending", do: row
    too = if too, do: " too", else: ""

    cond do
      attended == [] ->
        nil

      Messages.name_them?(attended) ->
        names =
          attended
          |> Enum.sort_by(&String.downcase(&1.member.name))
          |> Enum.map(&"#{&1.member.name}'s #{Service.Format.duration(minutes(&1))}")
          |> Service.Format.and_list()

        "#{names} go#{too}."

      true ->
        total = attended |> Enum.sum_by(&minutes/1) |> Service.Format.duration()
        "#{length(attended)} who attended lose #{total}#{too}."
    end
  end

  defp minutes(row), do: row.duration_in_minutes || 0
end
