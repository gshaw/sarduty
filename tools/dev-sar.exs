# Dev SAR: the Coast Range cast (App.CoastRange) as a team in the dev database, for
# trying a branch on made-up people instead of South Fraser's. Site admins join it as
# team admins, and attend the newest Missing hiker and sign up for the coming training.
# It has no D4H key, so nothing syncs and every D4H write fails.
#
#   mise exec -- mix run --no-start tools/dev-sar.exs           # seed, once
#   mise exec -- mix run --no-start tools/dev-sar.exs --reset   # delete it, then seed with today's dates
#
# Runs against the main checkout's dev database, or DEV_DB.

import Ecto.Query

alias App.Model.Activity
alias App.Model.Attendance
alias App.Model.Member
alias App.Model.Team
alias App.Operation.SeedCoastRange
alias App.Repo

if Mix.env() != :dev, do: Mix.raise("Dev SAR is for the dev database only.")

subdomain = "devsar"

# Started here, not by mix run, so Oban runs no jobs and the database can be swapped: the
# main checkout's, so a worktree seeds the database its server uses.
{list, 0} = System.cmd("git", ~w(worktree list --porcelain))
main = list |> String.split("\n") |> hd() |> String.replace_prefix("worktree ", "")
db = System.get_env("DEV_DB") || Path.join(main, "db/sarduty_dev.db")
repo = Application.get_env(:sarduty, Repo)
Application.put_env(:sarduty, Repo, Keyword.put(repo, :database, db))

Application.put_env(
  :sarduty,
  Oban,
  Keyword.merge(Application.get_env(:sarduty, Oban), queues: false, plugins: false)
)

{:ok, _} = Application.ensure_all_started(:sarduty)

existing = Repo.get_by(Team, subdomain: subdomain)

cond do
  existing && "--reset" in System.argv() ->
    # Foreign keys here don't cascade, so find every row under the team by hand: rows
    # with its team_id, then rows pointing at those, until a pass finds nothing new. Only
    # those ids are deleted, so other teams' rows are never touched.
    tables = List.flatten(Repo.query!("SELECT name FROM sqlite_master WHERE type = 'table'").rows)

    columns = fn t ->
      List.flatten(Repo.query!("SELECT name FROM pragma_table_info(?)", [t]).rows)
    end

    ids = fn t, where, args ->
      List.flatten(Repo.query!("SELECT id FROM #{t} WHERE #{where}", args).rows)
    end

    keys =
      for t <- tables,
          "id" in columns.(t),
          [parent, from] <-
            Repo.query!(~s|SELECT "table", "from" FROM pragma_foreign_key_list(?)|, [t]).rows,
          do: {t, parent, from}

    start =
      for t <- tables,
          t != "teams",
          "id" in columns.(t),
          "team_id" in columns.(t),
          into: %{},
          do: {t, MapSet.new(ids.(t, "team_id = ?", [existing.id]))}

    found =
      Stream.iterate({start, true}, fn {found, _} ->
        Enum.reduce(keys, {found, false}, fn {t, parent, from}, {found, grew} ->
          parents = found |> Map.get(parent, MapSet.new()) |> MapSet.to_list()
          have = Map.get(found, t, MapSet.new())

          more =
            if parents == [],
              do: [],
              else:
                ids.(t, "#{from} IN (SELECT value FROM json_each(?))", [Jason.encode!(parents)])

          new = MapSet.union(have, MapSet.new(more))
          {Map.put(found, t, new), grew or MapSet.size(new) > MapSet.size(have)}
        end)
      end)
      |> Enum.find(fn {_, grew} -> not grew end)
      |> elem(0)

    # One connection, so the pragma holds for every delete; the team goes last.
    Repo.checkout(fn ->
      Repo.query!("PRAGMA foreign_keys = OFF")

      for {t, set} <- found,
          MapSet.size(set) > 0,
          do:
            Repo.query!("DELETE FROM #{t} WHERE id IN (SELECT value FROM json_each(?))", [
              Jason.encode!(MapSet.to_list(set))
            ])

      # Join tables without an id of their own.
      for t <- tables,
          "id" not in columns.(t),
          [parent, from] <-
            Repo.query!(~s|SELECT "table", "from" FROM pragma_foreign_key_list(?)|, [t]).rows,
          set = Map.get(found, parent, MapSet.new()),
          MapSet.size(set) > 0,
          do:
            Repo.query!("DELETE FROM #{t} WHERE #{from} IN (SELECT value FROM json_each(?))", [
              Jason.encode!(MapSet.to_list(set))
            ])

      Repo.delete!(existing)
      Repo.query!("PRAGMA foreign_keys = ON")
    end)

    IO.puts("Deleted Dev SAR (team #{existing.id}).")

  existing ->
    IO.puts("Dev SAR is already team #{existing.id}. Pass --reset to seed it again.")
    System.halt(0)

  true ->
    :ok
end

now = DateTime.utc_now()

rows =
  SeedCoastRange.call(Repo, now, %{
    name: "Dev SAR",
    legal_name: "Dev Search and Rescue Society",
    abbreviated_name: "DSAR",
    subdomain: subdomain
  })

team = rows[{:team, :coastrange}]
activities = for {{:activity, _}, a} <- rows, do: a

latest = fn title ->
  activities |> Enum.filter(&(&1.title == title)) |> Enum.max_by(& &1.started_at, DateTime)
end

# A long description in D4H's HTML, like a real team's callout write-up.
hiker_description = """
<p>Coast Range SAR was requested by Ridgeview RCMP at 18:40 to search for a 58-year-old male hiker overdue from a day hike on the Cedar Flats loop. He left the Upper Cedar trailhead at about 09:00 and told his wife he would be home by 16:00. His car is still in the trailhead lot.</p>
<p><strong>Subject:</strong> 5'10", heavy build, grey beard. Last seen wearing a red rain shell, tan hiking pants, and a black toque. Carrying a small blue daypack, one litre of water, and a phone that has gone straight to voicemail since 14:15. Type 2 diabetic; his wife says he carries glucose tablets but no extra insulin. Experienced on local trails but has not hiked the north loop before.</p>
<p><strong>ICP:</strong> Upper Cedar trailhead parking lot, end of Cedar Flats Road. Report to the command post trailer, sign in with the Planning section, and wait for a briefing before deploying. Parking is tight: park along the road shoulder past the gate and leave the lot clear for the RCMP and the ambulance.</p>
<p><strong>Operational period 1 (18:40 to 02:00):</strong></p>
<ul>
<li>Team 1 (hasty): Cedar Flats loop clockwise from the trailhead to the falls viewpoint.</li>
<li>Team 2 (hasty): north loop counter-clockwise, including the washed-out bridge at Mile 3.</li>
<li>Team 3: attraction at the junctions with lights and whistles, every 15 minutes on the hour.</li>
<li>Team 4 (rope): standby at the falls viewpoint; the slope below the railing is steep and loose.</li>
<li>Drone team: thermal sweep of the creek drainage once it is dark enough.</li>
</ul>
<p><strong>Bring:</strong> 24-hour pack, headlamp and spare batteries, rain gear, warm layers, radio (channel plan in the briefing), and food for the night. Temperatures are expected to drop to 2&deg;C with rain after midnight.</p>
<p><strong>Update 23:15:</strong> Team 2 found fresh boot prints and a glucose tablet wrapper at the bridge washout. Search focus moved to the creek below. Mutual aid requested from Valley SAR for operational period 2.</p>
<p><strong>Update 01:40:</strong> Subject found by Team 2 about 400 m downstream of the bridge, cold and wet with a sprained ankle but conscious and talking. Packaged and carried out by Team 4 with a wheeled litter; handed to the ambulance at the trailhead at 03:05. All teams back at the ICP and signed out by 03:30. Stood down by RCMP at 03:35.</p>
<p>Thanks to everyone who came out on short notice. Please enter your hours and travel in SAR Duty, and get any gear that needs cleaning or repair back to the hall by Sunday. Debrief at the hall on Tuesday at 19:00.</p>
"""

hiker = latest.("Missing hiker") |> Ecto.Changeset.change(description: hiker_description) |> Repo.update!()

training =
  activities
  |> Enum.filter(&(&1.activity_kind == "exercise" and DateTime.after?(&1.started_at, now)))
  |> Enum.min_by(& &1.started_at, DateTime)

admins = Repo.all(from u in App.Accounts.User, where: u.is_admin, order_by: u.id)

for {user, i} <- Enum.with_index(admins) do
  name =
    user.email
    |> String.split("@")
    |> hd()
    |> String.split(~r/[._]/)
    |> Enum.map_join(" ", &String.capitalize/1)

  member =
    Repo.insert!(%Member{
      team_id: team.id,
      d4h_member_id: 9_190_000 + i,
      ref_id: "90#{i}",
      name: name,
      email: user.email,
      phone: "604-555-019#{i}",
      position: "Team leader",
      joined_at: now |> DateTime.add(-2000, :day) |> DateTime.truncate(:second),
      d4h_permission: 0,
      d4h_status: "OPERATIONAL"
    })

  for {activity, status, j} <- [{hiker, "attending", 1}, {training, "attending", 2}] do
    finished = if Activity.started?(activity, now), do: activity.finished_at

    Repo.insert!(%Attendance{
      member_id: member.id,
      activity_id: activity.id,
      d4h_attendance_id: 9_399_000 + i * 10 + j,
      status: status,
      started_at: activity.started_at,
      finished_at: finished || activity.finished_at,
      duration_in_minutes: DateTime.diff(activity.finished_at, activity.started_at, :minute),
      replied_at: activity.started_at |> DateTime.add(-2, :day) |> DateTime.truncate(:second)
    })
  end

  Repo.update_all(from(u in App.Accounts.User, where: u.id == ^user.id),
    set: [last_team_id: team.id]
  )

  IO.puts("#{name} (#{user.email}) is a team admin.")
end

IO.puts("""
Dev SAR is team #{team.id}.
  https://sarduty.gshaw.ca/teams/devsar/activities/#{hiker.id}/members (Missing hiker)
  https://sarduty.gshaw.ca/teams/devsar/activities/#{training.id}/members (#{training.title})
""")
