defmodule Web.MemberCollectionLive.GroupChoice do
  @moduledoc """
  The words for Add to group and Remove from group under the Members table: each choice's
  hint, the button, and its confirm, from the checked members and the picked group. The
  counts are App.Operation.SetGroupMembers.plan/3's, the same sums the click runs. The
  list follows writing.md's Choices for checked rows, and the button never names the
  group, since a title can run to any length: the hint and the confirm do.

  The team's Retiring group has its own words, since joining it cuts a login: Mark 3 as
  retiring, Mark 1 as not retiring (docs/members.md#retiring).

  `group` is nil until one is picked, then `%{title:, retiring?:, member_ids:}`, the ids a
  MapSet of who is in it now. `checked` are the checked members. All pure.
  """

  alias App.Operation.SetGroupMembers
  alias Service.Format
  alias Web.Components.Messages

  @type action :: :add | :remove
  @type group :: %{title: String.t(), retiring?: boolean(), member_ids: MapSet.t()} | nil

  @doc "The list's label for `action`."
  def label(:add), do: "Add to group"
  def label(:remove), do: "Remove from group"

  @doc "The checked members `action` changes in `group`, by name; [] without a group."
  def changes(_action, _checked, nil), do: []

  def changes(action, checked, group) do
    rows = for id <- group.member_ids, do: %{member_id: id}
    action |> SetGroupMembers.plan(checked, rows) |> Map.fetch!(:changes) |> Enum.map(& &1.member)
  end

  @doc """
  The line under the choice: what happens to the checked, with counts, and who it skips.
  With nothing checked, or no group yet, the same sentence without the group or counts.
  When it reaches nobody checked, why: "Everyone checked is in Rope team already."
  """
  def hint(:add, [], _group), do: "Adds the checked to the group you select. #{skip_any(:add)}"

  def hint(:remove, [], _group),
    do: "Takes the checked out of the group you select. #{skip_any(:remove)}"

  def hint(:add, checked, nil),
    do: "Adds #{the_checked(checked)} to the group you select. #{skip_any(:add)}"

  def hint(:remove, checked, nil),
    do: "Takes #{the_checked(checked)} out of the group you select. #{skip_any(:remove)}"

  def hint(action, checked, group) do
    changes = changes(action, checked, group)
    skipped = Enum.reject(checked, &(&1 in changes))

    if changes == [],
      do: nobody(action, group),
      else: reaches(action, group, reach(length(changes), length(checked)), skipped)
  end

  @doc """
  Why the button is greyed, for the hint beside it, or nil when it reaches someone: no
  group yet, or nobody checked it changes.
  """
  def waiting(_action, _checked, nil), do: "Select a group."

  def waiting(action, checked, group),
    do: if(changes(action, checked, group) == [], do: nobody(action, group))

  @doc ~s(The button for `count` members it changes: "Add 2 to group", or the label for 0.)
  def button_text(action, 0, _group), do: label(action)
  def button_text(:add, count, %{retiring?: true}), do: "Mark #{count} as retiring"
  def button_text(:remove, count, %{retiring?: true}), do: "Mark #{count} as not retiring"
  def button_text(:add, count, _group), do: "Add #{count} to group"
  def button_text(:remove, count, _group), do: "Remove #{count} from group"

  @doc """
  The button's `data-confirm` attributes for the members it changes, by name
  (/styles/confirm-dialog#many): up to 3 by name, then a count, and from 10 a box. Adding
  to a group kept by hand doesn't ask; Retiring asks both ways, since it cuts a login or
  gives one back. `service` is the team's, "D4H".
  """
  def confirm(_action, [], _group, _service), do: %{}
  def confirm(:add, _changes, %{retiring?: false}, _service), do: %{}

  def confirm(action, changes, group, service) do
    names = changes |> Enum.map(& &1.name) |> Enum.sort()
    members = names |> length() |> Format.count(one: "%d member", many: "%d members")
    who = Messages.names_or_count(names, members)

    {question, check} =
      case {action, group.retiring?} do
        {:remove, false} ->
          {"Remove #{who} from #{group.title}?", "I understand #{members} leave #{group.title}."}

        {:add, true} ->
          {"Mark #{who} as retiring? They can't log in to SAR Duty from now on. " <>
             "Take away their #{service} access too.", "I understand #{members} can't log in."}

        {:remove, true} ->
          {"Mark #{who} as not retiring? They can log in to SAR Duty again, " <>
             "and SAR Duty counts them again.", "I understand #{members} can log in again."}
      end

    Map.merge(%{"data-confirm" => question}, Messages.confirm_check(length(names), check))
  end

  defp skip_any(:add), do: "Anyone in it already is skipped."
  defp skip_any(:remove), do: "Anyone not in it is skipped."

  defp the_checked(checked), do: "the #{length(checked)} checked"

  # "the 1 checked", "all 3 checked", "2 of the 3 checked".
  defp reach(1, 1), do: "the 1 checked"
  defp reach(n, n), do: "all #{n} checked"
  defp reach(n, total), do: "#{n} of the #{total} checked"

  defp nobody(:add, %{retiring?: true}), do: "Everyone checked is retiring already."
  defp nobody(:remove, %{retiring?: true}), do: "Nobody checked is retiring."
  defp nobody(:add, group), do: "Everyone checked is in #{group.title} already."
  defp nobody(:remove, group), do: "Nobody checked is in #{group.title}."

  defp reaches(:add, %{retiring?: true}, reach, skipped),
    do:
      "Marks #{reach} as retiring. They can't log in to SAR Duty from now on." <>
        skipped(skipped, "is retiring already.", "are retiring already.")

  defp reaches(:remove, %{retiring?: true}, reach, skipped),
    do:
      "Marks #{reach} as not retiring. They can log in to SAR Duty again." <>
        skipped(skipped, "isn't retiring.", "aren't retiring.")

  defp reaches(:add, group, reach, skipped),
    do:
      "Adds #{reach} to #{group.title}." <>
        skipped(skipped, "is in it already.", "are in it already.")

  defp reaches(:remove, group, reach, skipped),
    do:
      "Takes #{reach} out of #{group.title}." <> skipped(skipped, "isn't in it.", "aren't in it.")

  # Who it skips, after a space: by name up to 3, "Avery Chen is in it already.", then a
  # count, "5 are in it already."
  defp skipped([], _one, _many), do: ""

  defp skipped(members, one, many) do
    names = members |> Enum.map(& &1.name) |> Enum.sort()

    cond do
      length(names) == 1 -> " #{hd(names)} #{one}"
      Messages.name_them?(names) -> " #{Format.and_list(names)} #{many}"
      true -> " #{length(names)} #{many}"
    end
  end
end
