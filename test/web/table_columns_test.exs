defmodule Web.TableColumnsTest do
  use ExUnit.Case, async: true

  # A filter changes a table's rows, not its columns (/styles/table). A column with :if
  # needs its reason here: the viewer may not see it, or no row in the view has a value.
  @hidden %{
    {"lib/web/components/equipment.ex", "@where?"} =>
      "nothing the member holds is inside a kit, so every Where is blank",
    {"lib/web/live/activity_live.ex",
     ~s|!@started? and (@view != "requested" or @reminded_shown?)|} =>
      "Replied: before the start only, and No reply has no reply dates",
    {"lib/web/live/activity_live.ex", ~s|@started? and @view in [nil, "attending"]|} =>
      "Start, Finish, and Duration: only rows that attended have times",
    {"lib/web/live/chore_collection_live.ex", "@selected"} =>
      "the checkboxes accept chores, and only Waiting has them",
    {"lib/web/live/chore_collection_live.ex", "@category"} =>
      "Accepted puts each table under its category's heading",
    {"lib/web/live/endorsement_collection_live.ex", "@current_team.id_cards_enabled"} =>
      "On card means nothing on a team with no ID cards",
    {"lib/web/live/member_collection_live.ex", "@standing?"} =>
      "team data, not the filter: every current member is active",
    {"lib/web/live/member_collection_live.ex", ~s|@details == "missing"|} =>
      "Missing says why a row matched Details: Missing",
    {"lib/web/live/member_collection_live.ex", "@retired?"} =>
      "only retired members have a Retired date",
    {"lib/web/live/member_groups_live.ex", "@team_admin? and @records?"} =>
      "Remove buttons, for a Records team's admins only",
    {"lib/web/live/member_qualifications_live.ex", "@team_admin? and @records?"} =>
      "Edit buttons, for a Records team's admins only",
    {"lib/web/live/org/admins_live.ex", "@sar_duty_admin?"} =>
      "Remove buttons, for SAR Duty admins only",
    {"lib/web/live/proposed_change_live.ex", "ChangeSet.waiting?(@change_set)"} =>
      "checkboxes pick what to send, so only while it waits",
    {"lib/web/live/proposed_change_live.ex", "!ChangeSet.waiting?(@change_set)"} =>
      "a result exists only once it is sent",
    {"lib/web/live/whiteboard_live.ex", "@team_admin?"} => "note actions, for team admins only"
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
