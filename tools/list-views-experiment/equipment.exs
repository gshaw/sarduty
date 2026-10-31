Code.require_file("tools/list-views-experiment/boot.exs")
alias App.ViewData.EquipmentList
spec = ListSpec.parse(File.read!("tools/list-views-experiment/specs/equipment.report"))
now = DateTime.utc_now()

for team <- App.Repo.all(App.Model.Team) do
  list = "Equipment (team #{team.id})"
  rows = team.id |> App.Model.EquipmentItem.get_all() |> EquipmentList.rows()
  places = rows |> Enum.map(& &1.place) |> Enum.uniq() |> Enum.take(4)
  cats = rows |> Enum.map(&EquipmentList.category(&1.item)) |> Enum.uniq() |> Enum.take(3)

  page = fn show, q, place, category, expires ->
    rows
    |> EquipmentList.narrow(place, category, %{})
    |> EquipmentList.expiring(expires, now)
    |> EquipmentList.filter(show, q, now)
    |> Enum.map(& &1.item.id)
  end

  cases =
    for(show <- ~w(all in-service unserviceable lost retired), do: {show, "", "", "", ""}) ++
      for(p <- places, do: {"all", "", p, "", ""}) ++
      for(c <- cats, do: {"in-service", "", "", c, ""}) ++
      [{"all", "", "", "", "soon"}, {"in-service", "rope", "", "", ""}, {"all", "1", "", "", ""}]

  for {show, q, place, category, expires} <- cases do
    picks = %{"show" => show, "q" => q, "place" => place, "category" => category, "expires" => expires}
            |> Map.reject(fn {_k, v} -> v == "" end)
    ours = ListSpec.ids(spec, team, picks, now)
    Check.same_set(list, inspect(picks), ours, page.(show, q, place, category, expires))
  end

  for {place, expires} <- [{"", ""}, {hd(places ++ [""]), ""}, {"", "soon"}] do
    narrowed = rows |> EquipmentList.narrow(place, "", %{}) |> EquipmentList.expiring(expires, now)
    theirs = Map.new(EquipmentList.show_values() -- ["all"], &{&1, length(EquipmentList.filter(narrowed, &1, "", now))})
    picks = %{"place" => place, "expires" => expires} |> Map.reject(fn {_k, v} -> v == "" end)
    Check.same(list, "tile counts #{inspect(picks)}", ListSpec.counts(spec, team, picks, now), theirs)
  end
end

Check.summary()
