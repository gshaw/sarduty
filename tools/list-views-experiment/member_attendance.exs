Code.require_file("tools/list-views-experiment/boot.exs")
alias App.ViewModel.AttendanceFilterViewModel, as: VM
import Ecto.Query

spec = ListSpec.parse(File.read!("tools/list-views-experiment/specs/member_attendance.report"))
now = DateTime.utc_now()

for team <- App.Repo.all(App.Model.Team) do
  list = "Member attendance (team #{team.id})"

  members =
    App.Repo.all(
      from at in App.Model.Attendance,
        join: m in assoc(at, :member),
        where: m.team_id == ^team.id,
        group_by: at.member_id,
        order_by: [desc: count(at.id)],
        limit: 3,
        select: at.member_id
    )

  tag = App.Repo.one(from t in App.Model.Tag, where: t.team_id == ^team.id, limit: 1)

  for member_id <- members do
    member = App.Model.Member |> App.Repo.get!(member_id) |> App.Repo.preload(:team)

    cases =
      [%{}, %{"when" => "all"}, %{"when" => "2024"}, %{"when" => "365d"}, %{"when" => "all", "tag" => "both"},
       %{"when" => "all", "tag" => "primary"}, %{"when" => "all", "tag" => "secondary"},
       %{"when" => "all", "tag" => "other"}, %{"when" => "all", "q" => "a"}] ++
        if(tag, do: [%{"when" => "all", "activity_tag" => tag.title}], else: [])

    for params <- cases do
      {:ok, opts, _} = VM.validate(params)
      first = VM.build_paginated_content(member, opts)

      theirs =
        Enum.flat_map(1..first.total_pages, fn n ->
          VM.build_paginated_content(member, %{opts | page: n}).entries |> Enum.map(& &1.id)
        end)

      ours = ListSpec.ids(spec, team, Map.put(params, "member", "#{member_id}"), now)
      Check.same_set(list, "member #{member_id} #{inspect(params)}", ours, theirs)
    end

    for sort <- ~w(date- date hours- hours id- id) do
      params = %{"sort" => sort, "page" => 1, "when" => "all"}
      {:ok, opts, _} = VM.validate(params)
      p = VM.build_paginated_content(member, opts)
      {ours, total} = ListSpec.page(spec, team, Map.put(params, "member", "#{member_id}"), now)
      # The page breaks no ties, so compare each row's sort key, not its id.
      key = fn ids ->
        rows = App.Repo.all(from at in App.Model.Attendance, where: at.id in ^ids) |> Map.new(&{&1.id, &1})
        field = %{"date" => :started_at, "hours" => :duration_in_minutes, "id" => :activity_id}[String.trim_trailing(sort, "-")]
        Enum.map(ids, &Map.fetch!(rows[&1], field))
      end

      Check.same(list, "member #{member_id} sort #{sort} (sort keys)", {key.(ours), total}, {key.(Enum.map(p.entries, & &1.id)), p.total_entries})
    end
  end
end

Check.summary()
