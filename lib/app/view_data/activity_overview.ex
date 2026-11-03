defmodule App.ViewData.ActivityOverview do
  @moduledoc """
  An activity's Overview tab: charts under the description, drawn by chart reports (#826)
  run on this one activity. A chart with nothing to draw is left out, so a new activity
  shows none. Its counts are the panel's line, on every tab.
  """
  alias App.Model.Activity
  alias App.Report
  alias App.Report.Context
  alias App.ViewData.ReportRecords

  @doc """
  The charts with something to draw, each `%{id:, title:, caption:, chart:, records:}`,
  run as the viewer: a member as a member, as the Dashboard runs its own.
  """
  def charts(team, %Activity{} = activity, now, team_admin?) do
    context = Context.new(team, now, team_admin?: team_admin?)

    for {id, title, caption, query} <- queries(activity),
        {:ok, view} <- [Report.page_in(context, query)],
        !empty?(view.chart) do
      %{
        id: id,
        title: title,
        caption: caption,
        chart: view.chart,
        records: ReportRecords.load(view.result, team, now)
      }
    end
  end

  # Each chart's report, on this activity alone. The id is an integer, never text a
  # person typed.
  defp queries(%Activity{id: id}) do
    [
      {"chart-sign-ups", "Sign-ups by day", "Members who signed up, by the day they replied.",
       """
       select date(replied_at), count(id)
       from attendance
       where activity.id = #{id} and replied_at is not null
         and (status = 'Signed up' or status = 'Attended')
       group by date(replied_at)
       order by date(replied_at)
       label count(id) 'Signed up'
       chart lines cumulative
       """}
    ]
  end

  @doc "Whether a chart has nothing to draw."
  def empty?(%{kind: :bars, data: %{rows: rows}}), do: rows == []
  def empty?(%{kind: :lines, data: %{labels: labels}}), do: labels == []

  def empty?(%{kind: :columns, data: %{columns: columns}}),
    do:
      Enum.all?(columns, fn column -> Enum.all?(Map.values(column.values), &(&1 in [0, nil])) end)

  def empty?(_chart), do: false
end
