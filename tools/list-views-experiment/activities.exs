Code.require_file("tools/list-views-experiment/boot.exs")
alias App.ViewModel.ActivityFilterViewModel, as: VM

spec = ListSpec.parse(File.read!("tools/list-views-experiment/specs/activities.report"))
now = DateTime.utc_now()

page_ids = fn team, params ->
  {:ok, opts, _} = VM.validate(params)
  first = VM.build_paginated_content(team, nil, opts)

  Enum.flat_map(1..first.total_pages, fn n ->
    VM.build_paginated_content(team, nil, %{opts | page: n}).entries |> Enum.map(& &1.id)
  end)
end

cases = [
  %{},
  %{"activity" => "incident"},
  %{"activity" => "exercise"},
  %{"activity" => "event"},
  %{"activity" => "chores"},
  %{"when" => "current"},
  %{"when" => "recent"},
  %{"when" => "past"},
  %{"when" => "future"},
  %{"when" => "2025"},
  %{"when" => "2024", "activity" => "incident"},
  %{"status" => "draft"},
  %{"status" => "published", "when" => "2025"},
  %{"hours" => "untagged"},
  %{"hours" => "two"},
  %{"fields" => "missing"},
  %{"q" => "rope"},
  %{"q" => "search", "when" => "2025"},
  %{"q" => "24-"},
  %{"q" => "Training"}
]

for team <- App.Repo.all(App.Model.Team) do
  list = "Activities (team #{team.id})"

  for params <- cases do
    picks = Map.put_new(params, "sort", "date-")
    ours = ListSpec.ids(spec, team, picks, now)
    theirs = page_ids.(team, params)
    Check.same_set(list, inspect(params), ours, theirs)
  end

  # Switch counts, as the tiles show them.
  for params <- [%{}, %{"when" => "2025"}, %{"status" => "draft", "q" => "x"}] do
    {:ok, opts, _} = VM.validate(params)
    theirs = VM.kind_counts(team, nil, opts) |> Map.delete("all")
    ours = ListSpec.counts(spec, team, params, now) |> Map.reject(fn {_k, v} -> v == 0 end)
    Check.same(list, "tile counts #{inspect(params)}", ours, theirs)
  end

  # Sorts and the first two pages, in order.
  for sort <- ~w(date- date hours- hours id- id), page <- [1, 2] do
    params = %{"sort" => sort, "page" => page, "when" => "2025"}
    {:ok, opts, _} = VM.validate(params)
    paginated = VM.build_paginated_content(team, nil, opts)
    {ours, total} = ListSpec.page(spec, team, params, now)
    Check.same(list, "sort #{sort} page #{page}", {ours, total}, {Enum.map(paginated.entries, & &1.id), paginated.total_entries})
  end
end

Check.summary()
