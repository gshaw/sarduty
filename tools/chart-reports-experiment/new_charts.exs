# Experiment (charts): charts the site doesn't draw today, as reports, on the busiest
# dev team. Each prints its shape's size and its time; nothing is compared.
Code.require_file("tools/chart-reports-experiment/boot.exs")
alias App.Report.Chart, as: ChartSpec

team = App.Repo.get!(App.Model.Team, String.to_integer(System.get_env("TEAM", "1")))
now = DateTime.utc_now() |> DateTime.truncate(:second)

for path <- Path.wildcard("tools/chart-reports-experiment/specs/new/*.report") do
  spec = ChartSpec.read(path)
  {us, out} = :timer.tc(fn -> ChartSpec.run(spec, team, %{}, now) end)

  case out do
    {:ok, %{data: data, before_data: before}} ->
      summary =
        case spec.kind do
          :week -> "7 x 24, #{data.rows |> List.flatten() |> Enum.sum()} in all, busiest hour #{data.rows |> List.flatten() |> Enum.max()}"
          :bars -> "#{length(data.rows)} bars, top #{inspect(hd(data.rows).value)}"
          :columns -> "#{length(data.columns)} columns x #{length(data.series)} series #{inspect(Enum.map(data.series, &elem(&1, 0)))}"
          :lines -> "#{length(data.labels)} points x #{length(data.series)} series, last #{inspect(data.series |> hd() |> Map.get(:values) |> List.last())}" <> if(before, do: ", a year earlier #{inspect(before.series |> hd() |> Map.get(:values) |> List.last())}", else: "")
          _ -> inspect(data)
        end

      IO.puts("ok   #{String.pad_trailing(spec.name, 28)} #{Float.round(us / 1000, 1)} ms  #{summary}")

    {:error, error} ->
      IO.puts("FAIL #{spec.name}: #{App.Report.Error.text(error)}")
  end
end
