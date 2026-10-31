Code.require_file("tools/list-views-experiment/boot.exs")
alias App.ViewModel.MemberFilterViewModel, as: VM
import Ecto.Query

spec = ListSpec.parse(File.read!("tools/list-views-experiment/specs/members.report"))
now = DateTime.utc_now()

for team <- App.Repo.all(App.Model.Team) do
  list = "Members (team #{team.id})"
  group = App.Repo.one(from g in App.Model.Group, where: g.team_id == ^team.id, order_by: [desc: g.id], limit: 1)
  tag = App.Repo.one(from t in App.Model.Tag, where: t.team_id == ^team.id, limit: 1)

  cases =
    [
      %{},
      %{"standing" => "all"},
      %{"standing" => "active"},
      %{"standing" => "away"},
      %{"standing" => "retiring"},
      %{"standing" => "retired"},
      %{"standing" => "not_a_person"},
      %{"when" => "all"},
      %{"when" => "2024"},
      %{"when" => "90d"},
      %{"when" => "365d", "standing" => "retired"},
      %{"details" => "missing"},
      %{"attended" => "90"},
      %{"attended" => "365", "standing" => "all"},
      %{"items" => "held"},
      %{"items" => "none", "standing" => "retired"},
      %{"access" => "some"},
      %{"access" => "none", "standing" => "all"},
      %{"q" => "an"},
      %{"q" => "1", "standing" => "all"}
    ] ++
      if(group, do: [%{"group" => group.id}], else: []) ++
      if(tag, do: [%{"activity_tag" => tag.title, "when" => "all"}], else: [])

  # The page takes a group's id; the spec, its title.
  to_picks = fn params ->
    case params do
      %{"group" => id} -> Map.put(params, "group", group.title) |> Map.put("_id", id)
      _ -> params
    end
    |> Map.delete("_id")
  end

  for params <- cases do
    theirs = VM.ids(team, params, now)
    ours = ListSpec.ids(spec, team, to_picks.(params), now)
    Check.same_set(list, inspect(params), ours, theirs)
  end

  for params <- [%{}, %{"when" => "all"}, %{"items" => "held", "q" => "zz"}] do
    {:ok, opts, _} = VM.validate(params, true)
    theirs = VM.standing_counts(team, opts, true, now)
    ours = ListSpec.counts(spec, team, params, now)
    ours = Map.take(ours, Map.keys(theirs))
    Check.same(list, "tile counts #{inspect(params)}", ours, theirs)
  end

  sorts = ~w(name role id date date- retired retired- duration duration- activities activities- attended attended-)

  for sort <- sorts, page <- [1, 2] do
    params = %{"sort" => sort, "page" => page, "standing" => "all", "when" => "2025"}
    {:ok, opts, _} = VM.validate(params, true)
    paginated = VM.build_paginated_content(team, opts, now)
    {ours, total} = ListSpec.page(spec, team, params, now)
    theirs = {Enum.map(paginated.entries, & &1.member.id), paginated.total_entries}
    Check.same(list, "sort #{sort} page #{page}", {ours, total}, theirs)
  end

  # The Activities and Duration columns, for the tag and period.
  params = %{"when" => "2025", "standing" => "all"} |> then(&if(tag, do: Map.put(&1, "activity_tag", tag.title), else: &1))
  {:ok, opts, _} = VM.validate(Map.put(params, "sort", "name"), true)
  first = VM.build_paginated_content(team, opts, now)
  theirs =
    Enum.flat_map(1..first.total_pages, fn n ->
      VM.build_paginated_content(team, %{opts | page: n}, now).entries
      |> Enum.map(&{&1.member.id, &1.activity_count, &1.total_minutes})
    end)
    |> Enum.sort()
  {text, given} = ListSpec.desugar(%{spec | page: nil}, params)
  {:ok, result} = App.Report.run(text, team, given, now)
  ours = result.rows |> Enum.map(fn [id, _n, _p, count, minutes, _l] -> {id, count, minutes} end) |> Enum.sort()
  Check.same(list, "Activities and Duration columns #{inspect(params)}", ours, theirs)
end

Check.summary()
