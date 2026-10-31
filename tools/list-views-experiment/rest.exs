Code.require_file("tools/list-views-experiment/boot.exs")
alias App.ViewModel.TaxCreditLetterFilterViewModel, as: TaxVM
alias App.ViewModel.MilestoneFilterViewModel, as: MileVM
alias Service.StringHelpers
import Ecto.Query
now = DateTime.utc_now()
groups = ListSpec.parse(File.read!("tools/list-views-experiment/specs/groups.report"))
tax = ListSpec.parse(File.read!("tools/list-views-experiment/specs/tax_letters.report"))
miles = ListSpec.parse(File.read!("tools/list-views-experiment/specs/milestones.report"))

for team <- App.Repo.all(App.Model.Team) do
  # Groups: the page's view and search, from their public parts. Out of step uses the
  # same BuildGroupRulePreview the page does, so it checks the shape, not the rule.
  all = App.Model.Group |> where(team_id: ^team.id) |> App.Repo.all()
  ruled = team.id |> App.Model.GroupRule.ruled_d4h_group_ids_query() |> App.Repo.all() |> MapSet.new()
  ctx = App.Operation.BuildGroupRulePreview.load(team)
  out = fn g ->
    MapSet.member?(ruled, g.d4h_group_id) and
      (fn p -> p.problems != [] or length(p.to_add) + length(p.to_remove) > 0 end).(App.Operation.BuildGroupRulePreview.preview(ctx, team, g))
  end
  for view <- ~w(all organization team out-of-step), q <- ["", "a"] do
    theirs = all |> Enum.filter(fn g -> case view do
      "organization" -> g.organization_owned
      "team" -> !g.organization_owned
      "out-of-step" -> out.(g)
      _ -> true end end) |> Enum.filter(&StringHelpers.matches?(&1.title, q)) |> Enum.map(& &1.id)
    Check.same_set("Groups (team #{team.id})", "#{view} q=#{q}", ListSpec.ids(groups, team, %{"view" => view, "q" => q}, now), theirs)
  end

  # Tax credit letters
  for year <- [2024, 2025], filter <- ~w(none any 50 200), letter <- [nil, "none", "made", "changed"], q <- ["", "a"],
      not (filter in ["none", "200"] and (letter != nil or q != "")) do
    {:ok, opts, _} = TaxVM.validate(%{"year" => year, "filter" => filter, "letter" => letter, "q" => q})
    records = TaxVM.find_all(team, opts, now)
    theirs = records |> TaxVM.shown(opts) |> Enum.map(& &1.member.id)
    picks = %{"year" => "#{year}", "filter" => filter, "letter" => letter, "q" => q, "sort" => "total"} |> Map.reject(fn {_, v} -> v in [nil, ""] end)
    ours = ListSpec.ids(tax, team, picks, now)
    Check.same("Tax letters (team #{team.id})", "#{inspect(picks)} in order", ours, theirs)
    if letter == nil and q == "" do
      counts = TaxVM.letter_counts(records) |> Map.delete(nil)
      Check.same("Tax letters (team #{team.id})", "tile counts #{inspect(picks)}", ListSpec.counts(tax, team, picks, now) |> Map.reject(fn {_, v} -> v == 0 end), counts)
    end
  end

  # Milestones
  ms = App.ViewData.MemberMilestones.for_team(team, now)
  member = ms |> Enum.map(& &1.member.id) |> Enum.frequencies() |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0} end) |> elem(0)
  for w <- ~w(all 30d 90d 365d 2025 2024), kind <- [nil, "hours", "years", "incidents"], m <- [nil, member], not (m != nil and kind != nil) do
    {:ok, opts, _} = MileVM.validate(%{"when" => w, "kind" => kind, "member" => m} |> Map.reject(fn {_, v} -> is_nil(v) end))
    theirs = ms |> MileVM.filter(opts, team.timezone, now) |> Enum.map(&{&1.member.id, &1.kind, &1.on})
    picks = %{"when" => w, "kind" => kind, "member" => m && "#{m}"} |> Map.reject(fn {_, v} -> is_nil(v) end)
    {text, given} = ListSpec.desugar(%{miles | page: nil}, picks)
    {:ok, result} = App.Report.run(text, team, given, now)
    ours = Enum.map(result.rows, fn [_id, mid, kind, on] -> {mid, String.to_atom(kind), Date.from_iso8601!(on)} end)
    Check.same("Milestones (team #{team.id})", "#{inspect(picks)} in order", ours, theirs)
  end
end

Check.summary()
