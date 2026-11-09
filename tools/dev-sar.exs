# Dev SAR: the Coast Range cast (App.CoastRange) as a SAR Duty Records team in the dev
# database, for trying a branch on made-up people instead of South Fraser's. Built like
# a Try a demo team (App.Operation.BuildDemoTeam.build_dev_team/3), so edits, photos, and
# the sync work as for any Records team. A site admin joins as the demo's visitor: a team
# admin beside Alex Chen, with an ID card, awards, and Missing hiker attended.
#
#   mise exec -- mix run --no-start tools/dev-sar.exs                        # build, once
#   mise exec -- mix run --no-start tools/dev-sar.exs --reset                # delete it, then build with today's dates
#   mise exec -- mix run --no-start tools/dev-sar.exs --reset --photo me.jpg # and set the site admin's photo
#   mise exec -- mix run --no-start tools/dev-sar.exs --email andrew…        # another site admin, the first by default
#
# Needs a local Records (docs/records.md): RECORDS_HOST and RECORDS_SARDUTY_KEY, its
# SARDUTY_KEY. Runs against the main checkout's dev database, or DEV_DB.

import Ecto.Query

alias App.Accounts.User
alias App.Adapter.D4H
alias App.Model.Member
alias App.Model.MemberCard
alias App.Model.Team
alias App.Operation.BuildDemoTeam
alias App.Operation.DeleteTeam
alias App.Operation.SetMemberPhoto
alias App.Repo

if Mix.env() != :dev, do: Mix.raise("Dev SAR is for the dev database only.")

{opts, _args} = OptionParser.parse!(System.argv(), strict: [reset: :boolean, photo: :string, email: :string])

# Never the real Records: a dev team there would be a stranger's to see.
if System.get_env("RECORDS_HOST") in [nil, ""],
  do: Mix.raise("Set RECORDS_HOST to a local Records (docs/records.md).")

subdomain = "devsar"

# Started here, not by mix run, so Oban runs no jobs and the database can be swapped: the
# main checkout's, so a worktree builds in the database its server uses.
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

unless D4H.records_sarduty_key?(), do: Mix.raise("Set RECORDS_SARDUTY_KEY to Records' SARDUTY_KEY.")

photo = if path = opts[:photo], do: File.read!(Path.expand(path))

case Repo.get_by(Team, subdomain: subdomain) do
  nil ->
    :ok

  existing ->
    if opts[:reset] do
      # In Records too, where a demo team goes at once.
      {:ok, %{rows: rows}} = DeleteTeam.purge(existing, reason: :admin)
      IO.puts("Deleted Dev SAR (team #{existing.id}, #{rows} rows).")
    else
      IO.puts("Dev SAR is already team #{existing.id}. Pass --reset to build it again.")
      System.halt(0)
    end
end

admins = from(u in User, where: u.is_admin, order_by: u.id) |> Repo.all()

user =
  if email = opts[:email],
    do: Enum.find(admins, &(&1.email == email)) || Mix.raise("No site admin #{email}."),
    else: List.first(admins) || Mix.raise("The dev database has no site admin.")

name =
  user.email
  |> String.split("@")
  |> hd()
  |> String.split(~r/[._]/)
  |> Enum.map_join(" ", &String.capitalize/1)

now = DateTime.utc_now()

{:ok, team} =
  BuildDemoTeam.build_dev_team(
    %{name: name, email: user.email},
    %{
      name: "Dev SAR",
      legal_name: "Dev Search and Rescue Society",
      abbreviated_name: "DSAR",
      subdomain: subdomain
    },
    now
  )

member = Repo.get_by!(Member, team_id: team.id, email: user.email)

if photo do
  :ok = SetMemberPhoto.call(team, member, photo, user, now)
end

Repo.update_all(from(u in User, where: u.id == ^user.id), set: [last_team_id: team.id])

card = team |> MemberCard.find_current(member)
site = "https://sarduty.gshaw.ca"

IO.puts("""
Dev SAR is team #{team.id}, Records team #{team.d4h_team_id}. #{name} (#{user.email}) is a team admin#{if photo, do: ", with a photo", else: ""}.
  #{site}/teams/devsar
  #{site}/teams/devsar/me
""")

if card, do: IO.puts("  #{site}#{Web.CardLinks.path(card)} (ID card)")
