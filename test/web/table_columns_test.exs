defmodule Web.TableColumnsTest do
  use ExUnit.Case, async: true

  # A filter changes a table's rows, not its columns (/styles/table). A column with :if
  # needs its reason here: the viewer may not see it, or no row in the view has a value.
  @hidden %{
    {"lib/web/live/group_live.ex", "!@ruled?"} =>
      "Remove buttons: a group with rules has its members picked by the rules",
    {"lib/web/live/member_collection_live.ex", "@group_form?"} =>
      "checkboxes add members to a group, for team admins on a team with groups to add to",
    {"lib/web/components/equipment.ex", "@where?"} =>
      "nothing the member holds is inside a kit, so every Where is blank",
    {"lib/web/live/activity_members_live.ex", "@changeable?"} =>
      "the checkboxes, for team admins: emails before and after the start, attendance until it's published",
    {"lib/web/live/activity_members_live.ex", "!@started?"} =>
      "Replied: replies close at the start, and from it the table shows attendance",
    {"lib/web/live/activity_members_live.ex", "!@started? and @reminded != %{}"} =>
      "Reminder: reminders go before the start, and the column waits for the activity's first",
    {"lib/web/live/activity_members_live.ex", "@started?"} =>
      "Start, Finish, and Hours: times come with attendance, from the start",
    {"lib/web/components/travel_tab.ex", "!@locked?"} =>
      "the checkboxes set travel, and a published activity's travel cannot change",
    {"lib/web/live/tax_credit_letter_collection_live.ex", "is_nil(@refusal)"} =>
      "the checkboxes: a year that isn't over can't be emailed, so it has no actions (#995)",
    {"lib/web/live/chore_collection_live.ex", "@selected"} =>
      "the checkboxes accept chores, and only Waiting has them",
    {"lib/web/live/chore_collection_live.ex", "@category"} =>
      "Accepted puts each table under its category's heading",
    {"lib/web/live/endorsement_collection_live.ex", "@current_team.id_cards_enabled"} =>
      "On card means nothing on a team with no ID cards",
    {"lib/web/live/member_collection_live.ex", "@retired?"} =>
      "only retired members have a Retired date",
    {"lib/web/live/member_groups_live.ex", "@team_admin?"} =>
      "Remove buttons, for team admins only",
    {"lib/web/live/member_qualifications_live.ex", "@team_admin? and @records?"} =>
      "Edit buttons, for a Records team's admins only",
    {"lib/web/live/org/admins_live.ex", "@sar_duty_admin?"} =>
      "Remove buttons, for SAR Duty admins only",
    {"lib/web/live/activity_live.ex", "@team_admin? and !@activity.deleted_at"} =>
      "Change links, for team admins on an activity not deleted",
    {"lib/web/live/whiteboard_live.ex", "@team_admin?"} => "note actions, for team admins only",
    {"lib/web/live/activity_org_form_live.ex", "@table.kind == :member"} =>
      "a form's rows are a report's members or its items, never both: Member for people",
    {"lib/web/live/activity_org_form_live.ex", "@table.kind == :item"} =>
      "a form's rows are a report's members or its items, never both: Item for equipment",
    {"lib/web/live/activity_org_form_live.ex", "@table.total"} =>
      "a row's total is the form's last value worked out for it, and a form may work out none"
  }

  test "every column that hides has a reason" do
    found =
      for path <- Path.wildcard("lib/web/**/*.{ex,heex}"),
          [_, condition] <- Regex.scan(~r/<:col\b[^>]*?:if=\{(.*?)\}\s/s, File.read!(path)),
          do: {path, condition}

    unlisted = found |> Enum.uniq() |> Enum.reject(&Map.has_key?(@hidden, &1))

    assert unlisted == [],
           "A filter changes rows, not columns. Show the column, or add its reason here:\n" <>
             Enum.map_join(unlisted, "\n", fn {path, condition} -> "#{path}: #{condition}" end)

    stale = Map.keys(@hidden) -- found
    assert stale == [], "No longer in the code, so remove: #{inspect(stale)}"
  end
end
