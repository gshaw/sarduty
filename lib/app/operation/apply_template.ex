defmodule App.Operation.ApplyTemplate do
  @moduledoc """
  Applies templates to an activity (#162, #307, #564): fills in its empty fields, writes
  the items and tags to D4H as equipment usages and the activity's tags, then adds the
  groups' members. A refusal leaves the rest unsent. Apply a template sends what its list
  holds; Add activity sends one template's adds on the activity it just added (#747).

  adds/3 decides what a template adds, add_tags/3 combines tags, and result/3 and
  refused/2 word what went; call/5 reads and writes.
  """

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.Team
  alias App.Model.Template
  alias App.Operation.ChangeActivityEquipment
  alias App.Operation.InviteMembers
  alias App.Operation.SaveCustomFields

  @doc """
  Sends `adds` to the activity: `fills` first, then the `lines` (as
  ChangeActivityEquipment.add/6 takes them) and `tags`, then the `groups`' members. A
  `%Template{}` sends what adds/3 says it adds. `{:ok, flash_kind, text}`, or
  `{:error, text}` when nothing went.
  """
  def call(%Team{} = team, %User{} = user, %Activity{} = activity, %Template{} = template, now) do
    fields = CustomField.get_all(team.id, activity.activity_kind)
    call(team, user, activity, adds(template, activity, fields), now)
  end

  def call(%Team{} = team, %User{} = user, %Activity{} = activity, %{fills: fills} = adds, now) do
    with :ok <- fill_fields(team, activity, fills, user, now),
         do: add_after_fields(team, user, activity, adds, now)
  end

  defp add_after_fields(team, user, activity, %{fills: fills} = adds, now) do
    case add_equipment(team, activity, adds.lines, adds.tags, user, now) do
      {:ok, rows} ->
        invited = invite(team, activity, adds.groups, user, now)
        {kind, text} = result(map_size(fills), rows, invited)
        {:ok, kind, text}

      {:error, text} ->
        refused(map_size(fills), text)
    end
  end

  @doc """
  What `template` adds to `activity`, as call/5 takes it: the fields of the activity's
  kind (`custom_fields`) it has empty, the items in service with their hours, the tags it
  lacks, and the groups.
  """
  def adds(%Template{} = template, %Activity{} = activity, custom_fields) do
    lines =
      for line <- template.template_items, EquipmentItem.in_service?(line.equipment_item) do
        %{item: line.equipment_item, minutes: line.minutes, km: nil}
      end

    %{
      fills: SaveCustomFields.fill_empty(%{}, activity, custom_fields, template.custom_values),
      lines: lines,
      tags: add_tags([], Template.tags(template), activity.tags),
      groups: Template.groups(template)
    }
  end

  @doc """
  `tags` with a template's `new` tags added, A to Z, leaving out any the activity has by
  title (`titles`). The send reads D4H again, so a stale title only means a tag goes
  unlisted.
  """
  def add_tags(tags, new, titles) do
    titles = titles || []

    (tags ++ Enum.reject(new, &(&1.title in titles)))
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&String.downcase(&1.title))
  end

  @doc """
  The flash once the items and tags went, as `{kind, text}`: how many fields were
  `filled`, the equipment `rows`, then the groups' members. `invited` is nil with no
  groups, `{:ok, result, day}` from InviteMembers.call/6, `:started`, or `{:error, text}`.
  The text is empty for adds with nothing in them.
  """
  def result(filled, rows, invited) do
    {kind, text} = invite_result(rows, invited)
    {kind, Enum.join(fields_text(filled) ++ List.wrap(text), " ")}
  end

  @doc """
  The items and tags were refused with `text`. Once fields were `filled`, the page leaves
  to say so, as for a refused invite: `{:ok, :error, text}`. Otherwise nothing went:
  `{:error, text}`.
  """
  def refused(0, text), do: {:error, text}
  def refused(filled, text), do: {:ok, :error, "#{count_fields(filled)} filled in. #{text}"}

  @doc """
  What adding the groups' members did, from InviteMembers.call/6's result: "8 members
  added.", then the rows that did not go and why, then how many were away on `day`. No
  rows and nobody away means everyone was on the activity already.
  """
  def invite_text(%{rows: [], away: []}, _day),
    do: "Everyone in those groups is on the activity already."

  def invite_text(%{rows: rows, away: away}, day),
    do: (InviteMembers.result_lines(rows) ++ away_text(away, day)) |> Enum.join(" ")

  defp away_text([], _day), do: []

  defp away_text(away, day) do
    away
    |> length()
    |> Service.Format.count(
      one: "1 member away on #{day} was left out.",
      many: "%d members away on #{day} were left out."
    )
    |> List.wrap()
  end

  # Nothing for a template that only fills in fields.
  defp invite_result([], nil), do: {:info, nil}

  defp invite_result(rows, nil),
    do:
      {ChangeActivityEquipment.flash_kind(rows),
       ChangeActivityEquipment.result_text(rows, "added")}

  defp invite_result(rows, invited) do
    {kind, text} =
      case invited do
        {:ok, result, day} ->
          {ChangeActivityEquipment.flash_kind(rows ++ result.rows), invite_text(result, day)}

        # A template still logs equipment after an activity, but adds nobody.
        :started ->
          {ChangeActivityEquipment.flash_kind(rows),
           "Its groups were left out: the activity has started."}

        {:error, text} ->
          {:error, text}
      end

    if rows == [],
      do: {kind, text},
      else: {kind, "#{ChangeActivityEquipment.result_text(rows, "added")} #{text}"}
  end

  defp fields_text(0), do: []
  defp fields_text(filled), do: [count_fields(filled) <> " filled in."]

  defp fill_fields(_team, _activity, fills, _user, _now) when fills == %{}, do: :ok

  defp fill_fields(team, activity, fills, user, now) do
    case SaveCustomFields.call(team, activity, fills, user, now) do
      {:ok, _activity} -> :ok
      {:error, text} -> {:error, "The fields were not sent. #{text}"}
    end
  end

  defp add_equipment(_team, _activity, [], [], _user, _now), do: {:ok, []}

  defp add_equipment(team, activity, lines, tags, user, now),
    do: ChangeActivityEquipment.add(team, activity, lines, tags, user, now)

  defp invite(_team, _activity, [], _user, _now), do: nil

  defp invite(team, activity, groups, user, now) do
    picks = InviteMembers.group_picks(team, groups, now)

    case InviteMembers.call(team, activity, picks, user, :template, now) do
      {:ok, result} -> {:ok, result, Service.Format.month_day(activity.started_at, team.timezone)}
      {:error, :started} -> :started
      {:error, reason} -> {:error, InviteMembers.error_text(team, reason)}
    end
  end

  defp count_fields(n), do: Service.Format.count(n, one: "%d field", many: "%d fields")
end
