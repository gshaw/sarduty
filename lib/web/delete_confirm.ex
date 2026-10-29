defmodule Web.DeleteConfirm do
  @moduledoc """
  The confirm dialog a record's Delete action opens, as `data-confirm` attributes for
  `/styles/confirm-dialog`. A delete has no page of its own (docs/urls.md): the dialog
  says what goes with it, and one that takes members' work asks for the box ticked (#651).
  """

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Attendance
  alias App.Model.GroupRule
  alias App.Model.MemberQualificationAward
  alias App.Model.Template
  alias App.Repo
  alias Service.Format

  @doc "An activity with attendance asks for the box ticked."
  def activity(team, activity, now) do
    gone = "It leaves every list and letter. Take attendance stops taking scans for it."

    case Attendance.attended_count(activity, now) do
      0 ->
        simple("Delete #{activity.title}? #{gone}", "Delete activity")

      count ->
        members = Format.count(count, one: "%d member", many: "%d members")

        ticked(team, "Delete the activity #{activity.title}?", "Delete activity",
          items: ["Its attendance for #{members} stops counting.", gone],
          lost: "the attendance for #{members} is lost"
        )
    end
  end

  @doc "An equipment item: its activities lose it, so Retired is offered instead."
  def item(item) do
    simple(
      "Delete #{item.title}? Its activities lose it too. To keep its history, set its status to Retired instead.",
      "Delete item"
    )
  end

  @doc "A qualification takes its awards with it."
  def qualification(team, qualification) do
    case MemberQualificationAward.holder_count(qualification) do
      0 ->
        simple("Delete #{qualification.title}? Nobody holds it.", "Delete qualification")

      count ->
        holders = Format.count(count, one: "%d member loses", many: "%d members lose")

        ticked(team, "Delete the qualification #{qualification.title}?", "Delete qualification",
          items: ["#{holders} it."],
          lost: "#{holders} it"
        )
    end
  end

  @doc """
  A group takes its members and rules with it, and stops what names it: other groups'
  rules, templates that add its members, and the attendance check. `context` is
  `BuildGroupRulePreview.load/1`'s, and `templates` is `template_titles/2`'s.
  """
  def group(team, group, member_count, context, templates) do
    own_rules = Map.get(context.rules, group.d4h_group_id, [])
    leave = Format.count(member_count, one: "%d member leaves", many: "%d members leave")

    items =
      Enum.reject(
        [
          if(member_count == 0, do: "Nobody is in it.", else: "Its #{leave} it."),
          if(own_rules != [],
            do:
              "Its #{Format.count(length(own_rules), one: "rule is", many: "%d rules are")} deleted."
          ),
          rules_text(naming_groups(context, group)),
          templates_text(templates),
          if(team.watch_d4h_group_id == group.d4h_group_id,
            do: "The attendance check stops until you select another group."
          )
        ],
        &is_nil/1
      )

    case group_lost(member_count, own_rules, leave) do
      nil ->
        simple("Delete #{group.title}? #{Enum.join(items, " ")}", "Delete group")

      lost ->
        ticked(team, "Delete the group #{group.title}?", "Delete group", items: items, lost: lost)
    end
  end

  @doc "The titles of the templates that add a group's members, A to Z."
  def template_titles(team, group) do
    Template
    |> join(:inner, [t], tg in assoc(t, :template_groups))
    |> where([t, tg], t.team_id == ^team.id and tg.group_id == ^group.id)
    |> order_by([t], asc: t.title)
    |> select([t], t.title)
    |> Repo.all()
  end

  # Red, though the Actions link isn't a red button.
  defp simple(message, button),
    do: %{
      "data-confirm" => message,
      "data-confirm-button" => button,
      "data-confirm-danger" => true
    }

  defp ticked(team, message, button, items: items, lost: lost),
    do: %{
      "data-confirm" => message,
      "data-confirm-list" => Jason.encode!(items),
      "data-confirm-warning" => "#{D4H.service_name(team)} can't bring it back.",
      "data-confirm-check" => "I understand #{lost}.",
      "data-confirm-button" => button,
      "data-confirm-danger" => true
    }

  defp group_lost(0, _own_rules, _leave), do: nil
  defp group_lost(_count, [], leave), do: "#{leave} it"

  defp group_lost(count, _own_rules, _leave),
    do: "#{Format.count(count, one: "%d member", many: "%d members")} and its rules are lost"

  defp naming_groups(context, group) do
    context.rules
    |> GroupRule.used_by(group.d4h_group_id)
    |> Enum.map(&context.groups[&1])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.title)
    |> Enum.sort()
  end

  defp rules_text([]), do: nil

  defp rules_text(groups),
    do: "The rules of #{Format.and_list(groups)} stop working until you change them."

  defp templates_text([]), do: nil
  defp templates_text([one]), do: "The template #{one} stops adding its members."

  defp templates_text(templates),
    do: "The templates #{Format.and_list(templates)} stop adding its members."
end
