defmodule Web.ActivityMembersLive.Action do
  @moduledoc """
  One change on an activity's Members tab (#766): a team admin checks members in the
  tables, picks a change from one list, and presses one button. Web.ActivityMembersLive
  lists every change in its `@actions`, in the list's order; each is a module with this
  behaviour.

  A change applies in place, through an operation, and the tables update on the tab
  (`run/1` answers `{:in_place, change}`). Or it opens a step (`{:step, live_action}`):
  the module is then a LiveComponent too, drawn in the tab's place on a `live_action`
  route of the same LiveView, such as `/members/remind`, so the ticks never leave the
  page. See Web.ActivityMembersLive for the step's rules. A step gets `team`, `activity`,
  `user`, `checked`, `standings`, `counts` (the panel's), `service`, and `back`, the
  tab's path, and draws everything under the page's title.

  `ctx` is `%{activity:, team:, now:, retiring:}`, with the team's retiring member ids. `checked` are the checked members' rows, one per
  member as the tab shows them (App.ViewData.ActivityMembers), each with its `member`,
  `status`, and `duration_in_minutes`.
  """

  @type ctx :: %{activity: map(), team: map(), now: DateTime.t(), retiring: MapSet.t()}

  @doc ~s(The list's value, also in ids: "absent".)
  @callback value() :: String.t()

  @doc ~s(The list's label: "Absent".)
  @callback label() :: String.t()

  @doc "The line under the label: what the change does."
  @callback hint(ctx()) :: String.t()

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
end
