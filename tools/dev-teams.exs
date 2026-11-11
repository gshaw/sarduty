# The dev teams: the made-up cast as SAR Duty Records teams in the dev database, for
# trying a branch on made-up people instead of South Fraser's (#963).
#
#   https://sarduty.gshaw.ca/teams/coastrange   Coast Range SAR (App.CoastRange)
#   https://sarduty.gshaw.ca/teams/silverbasin  Silver Basin SAR (App.SilverBasin)
#   https://sarduty.gshaw.ca/orgs/wesara        WESARA, their organization
#
# Built like a Try a demo (App.Operation.BuildDemoTeam.build_dev_teams/2), so edits,
# photos, and the sync work as for any Records team, but with no demo row: they keep
# their addresses, never expire, and show no banner. A site admin joins Coast Range as
# the demo's visitor: a team admin beside Alex Chen, with an ID card, awards, and Missing
# hiker attended. SAR Duty admins open every organization; Morgan Ellis and Rowan Pike
# are WESARA's organization admins, logging in by code from /dev/mailbox. WESARA's
# made-up Task report is on, to try forms and Publish (App.Operation.AddDemoForms).
#
#   mise exec -- mix run --no-start tools/dev-teams.exs                        # build, once
#   mise exec -- mix run --no-start tools/dev-teams.exs --reset                # delete them, then build with today's dates
#   mise exec -- mix run --no-start tools/dev-teams.exs --reset --photo me.jpg # and set the site admin's photo
#   mise exec -- mix run --no-start tools/dev-teams.exs --email andrew…        # another site admin, the first by default
#
# Needs a local Records (docs/records.md): RECORDS_HOST and RECORDS_SARDUTY_KEY, its
# SARDUTY_KEY. Runs against the main checkout's dev database, or DEV_DB.

import Ecto.Query

alias App.Accounts.User
alias App.Adapter.D4H
alias App.Model.Member
alias App.Model.MemberCard
alias App.Model.Organization
alias App.Model.Team
alias App.Operation.BuildDemoTeam
alias App.Operation.DeleteTeam
alias App.Operation.SetMemberPhoto
alias App.Repo

if Mix.env() != :dev, do: Mix.raise("The dev teams are for the dev database only.")

{opts, _args} = OptionParser.parse!(System.argv(), strict: [reset: :boolean, photo: :string, email: :string])

# Never the real Records: a dev team there would be a stranger's to see.
if System.get_env("RECORDS_HOST") in [nil, ""],
  do: Mix.raise("Set RECORDS_HOST to a local Records (docs/records.md).")

subdomains = ["coastrange", "silverbasin"]
slug = "wesara"

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

existing = from(t in Team, where: t.subdomain in ^subdomains) |> Repo.all()
organization = Repo.get_by(Organization, slug: slug)

cond do
  existing == [] and organization == nil ->
    :ok

  opts[:reset] ->
    # In Records too, where a demo team goes at once.
    for team <- existing do
      {:ok, %{rows: rows}} = DeleteTeam.purge(team, reason: :admin)
      IO.puts("Deleted #{team.name} (team #{team.id}, #{rows} rows).")
    end

    if organization do
      Repo.delete!(organization)
      IO.puts("Deleted #{organization.short_name} (organization #{organization.id}).")
    end

  true ->
    IO.puts("The dev teams are built already. Pass --reset to build them again.")
    System.halt(0)
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

{:ok, team} = BuildDemoTeam.build_dev_teams(%{name: name, email: user.email}, now)

member = Repo.get_by!(Member, team_id: team.id, email: user.email)

if photo do
  :ok = SetMemberPhoto.call(team, member, photo, user, now)
end

Repo.update_all(from(u in User, where: u.id == ^user.id), set: [last_team_id: team.id])

card = team |> MemberCard.find_current(member)
site = "https://sarduty.gshaw.ca"
basin = Repo.get_by!(Team, subdomain: "silverbasin")

IO.puts("""
Coast Range SAR is team #{team.id} and Silver Basin SAR team #{basin.id}, Records teams #{team.d4h_team_id} and #{basin.d4h_team_id}, in WESARA. #{name} (#{user.email}) is a Coast Range team admin#{if photo, do: ", with a photo", else: ""}.
  #{site}/teams/coastrange
  #{site}/teams/coastrange/me
  #{site}/teams/silverbasin
  #{site}/orgs/wesara
""")

if card, do: IO.puts("  #{site}#{Web.CardLinks.path(card)} (ID card)")
