Code.require_file("tools/list-views-experiment/boot.exs")
now = DateTime.utc_now()
import Ecto.Query
specs = ~w(activities members member_attendance qualifications awards_expiring qualification_awards equipment groups tax_letters milestones)
member_for = fn team -> App.Repo.one(from(a in App.Model.Attendance, join: m in assoc(a, :member), where: m.team_id == ^team.id, group_by: a.member_id, order_by: [desc: count(a.id)], limit: 1, select: a.member_id)) end
qual_for = fn team -> App.Repo.one(from(q in App.Model.Qualification, where: q.team_id == ^team.id, limit: 1, select: q.id)) end
for team_id <- [1, 3, 6] do
  team = App.Repo.get!(App.Model.Team, team_id)
  for name <- specs do
    spec = ListSpec.parse(File.read!("tools/list-views-experiment/specs/#{name}.report"))
    picks = %{"page" => 1, "member" => "#{member_for.(team)}", "qualification" => "#{qual_for.(team)}"}
    picks = if spec.sorts != [], do: Map.put(picks, "sort", hd(spec.sorts).value), else: picks
    {page_us, _} = :timer.tc(fn -> if spec.page, do: ListSpec.page(spec, team, picks, now), else: ListSpec.ids(spec, team, picks, now) end)
    has_switch = Enum.any?(spec.filters, &(&1.kind == :switch))
    {count_us, _} = :timer.tc(fn -> if has_switch, do: ListSpec.counts(spec, team, picks, now), else: nil end)
    IO.puts("team #{team_id} #{String.pad_trailing(name, 22)} rows #{div(page_us, 1000)} ms, tile counts #{div(count_us, 1000)} ms")
  end
end
