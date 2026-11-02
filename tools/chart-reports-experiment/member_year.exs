# Experiment (charts): a member's year page (/teams/:subdomain/me/activities?year=) from
# reports scoped to one member, against App.ViewData.MemberYear. Up to 15 members per
# team with attendance, for 2024, 2025, and 2026.
Code.require_file("tools/chart-reports-experiment/boot.exs")
alias App.Report.Chart, as: ChartSpec

import Ecto.Query
alias App.Model.{Activity, Attendance, Member, Team}
alias App.ViewData.{MemberRecords, MemberYear}

dir = "tools/chart-reports-experiment/specs/member"
spec = fn name -> ChartSpec.read(Path.join(dir, name <> ".report")) end
now = DateTime.utc_now() |> DateTime.truncate(:second)

for team <- App.Repo.all(Team) do
  hours_tags = Activity.hours_tags(team)

  ids =
    from(r in Attendance, join: m in assoc(r, :member), where: m.team_id == ^team.id and r.status == "attending",
      group_by: r.member_id, order_by: [desc: count(r.id)], limit: 15, select: r.member_id)
    |> App.Repo.all()

  for id <- ids, year <- [2024, 2025, 2026] do
    member = Member |> App.Repo.get!(id) |> App.Repo.preload(:team)
    label = "team #{team.id} member #{id} #{year}"
    rows = MemberRecords.attendances(member, year, now)
    before = MemberRecords.attendances(member, year - 1, now)
    page = MemberYear.summary(rows, before, year, now, team.timezone, hours_tags)
    given = %{"member" => "#{id}", "year" => "#{year}"}

    {:ok, a} = ChartSpec.run(spec.("activities-this-year"), team, given, now)
    Check.same("Activities stat", label, {a.data.value, a.before_data.value}, page.versus.activities)
    Check.same("Activities line", label, a.data.spark, page.monthly.activities)

    {:ok, i} = ChartSpec.run(spec.("incidents-this-year"), team, given, now)
    Check.same("Incidents stat", label, {i.data.value, i.before_data.value}, page.versus.incidents)
    Check.same("Incidents line", label, i.data.spark, page.monthly.incidents)

    {:ok, h} = ChartSpec.run(spec.("hours-by-month"), team, given, now)
    ours = Enum.map(h.data.columns, &{&1.label, Map.reject(&1.values, fn {_k, v} -> v == 0 end)})
    theirs = Enum.map(page.hour_columns, &{&1.label, Map.reject(&1.values, fn {_k, v} -> v == 0 end)})
    Check.same("Hours by month", label, ours, theirs)
  end
end

Check.summary()
