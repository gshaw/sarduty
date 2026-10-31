Code.require_file("tools/list-views-experiment/boot.exs")
import Ecto.Query
alias App.Model.{MemberQualificationAward, Qualification, GroupMember}
alias Service.StringHelpers

quals = ListSpec.parse(File.read!("tools/list-views-experiment/specs/qualifications.report"))
expiring = ListSpec.parse(File.read!("tools/list-views-experiment/specs/awards_expiring.report"))
awards = ListSpec.parse(File.read!("tools/list-views-experiment/specs/qualification_awards.report"))
now = DateTime.utc_now()

# The pages keep these steps in private functions; this mirrors them from their public parts.
page_quals = fn team, view, q ->
  team.id
  |> Qualification.get_all()
  |> Enum.filter(fn x ->
    case view do
      "organization" -> x.organization_owned
      "team" -> !x.organization_owned
      _ -> true
    end
  end)
  |> Enum.filter(&StringHelpers.matches?(&1.title, q))
  |> Enum.map(& &1.id)
end

page_expiring = fn team, within, q, group_id ->
  ids = GroupMember.member_ids(team.id, group_id)

  team.id
  |> MemberQualificationAward.expiring(now, DateTime.add(now, within, :day))
  |> Enum.filter(&((StringHelpers.matches?(&1.member_name, q) or StringHelpers.matches?(&1.qualification, q)) and (is_nil(ids) or MapSet.member?(ids, &1.member_id))))
  |> Enum.map(& &1.award_id)
end

page_awards = fn team, qualification_id, view, q, group_id ->
  list =
    MemberQualificationAward
    |> where([mqa], mqa.qualification_id == ^qualification_id)
    |> join(:inner, [mqa], m in assoc(mqa, :member))
    |> order_by([mqa, m], asc: m.name, desc: mqa.starts_at)
    |> preload([mqa, m], member: m)
    |> App.Repo.all()

  {active, expired} = MemberQualificationAward.split_by_member(list, now)
  ids = GroupMember.member_ids(team.id, group_id)
  shown = case view do
    "active" -> active
    "expired" -> expired
    "all" -> active ++ expired
  end
  shown |> Enum.filter(&(StringHelpers.matches?(&1.member.name, q) and (is_nil(ids) or MapSet.member?(ids, &1.member.id)))) |> Enum.map(& &1.id)
end

for team <- App.Repo.all(App.Model.Team) do
  group = App.Repo.one(from g in App.Model.Group, where: g.team_id == ^team.id, order_by: [desc: g.id], limit: 1)

  for {view, q} <- [{"all", ""}, {"organization", ""}, {"team", ""}, {"all", "first"}, {"all", "a"}] do
    ours = ListSpec.ids(quals, team, %{"view" => view, "q" => q}, now)
    Check.same_set("Qualifications (team #{team.id})", "#{view} q=#{q}", ours, page_quals.(team, view, q))
  end

  for within <- [30, 60, 90, 180], {q, g} <- [{"", nil}, {"a", nil}] ++ if(group, do: [{"", group}], else: []) do
    picks = %{"within" => "#{within}", "q" => q} |> then(&if(g, do: Map.put(&1, "group", g.title), else: &1))
    ours = ListSpec.ids(expiring, team, picks, now)
    Check.same_set("Expiring awards (team #{team.id})", inspect(picks), ours, page_expiring.(team, within, q, g && g.id))
  end

  for qual <- App.Repo.all(from q in Qualification, where: q.team_id == ^team.id, limit: 8),
      {view, q, g} <- [{"active", "", nil}, {"expired", "", nil}, {"all", "", nil}, {"all", "e", nil}] ++ if(group, do: [{"all", "", group}], else: []) do
    picks = %{"view" => view, "q" => q, "qualification" => "#{qual.id}"} |> then(&if(g, do: Map.put(&1, "group", g.title), else: &1))
    ours = ListSpec.ids(awards, team, picks, now)
    Check.same_set("Qualification awards (team #{team.id})", "#{qual.id} #{view} q=#{q} group=#{g && g.id}", ours, page_awards.(team, qual.id, view, q, g && g.id))
  end
end

Check.summary()
