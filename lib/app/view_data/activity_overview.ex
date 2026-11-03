defmodule App.ViewData.ActivityOverview do
  @moduledoc """
  An activity's Overview tab: stat boxes under the map, and charts under the
  description, drawn by chart reports (#826) run on this one activity.

  Before the start the stats are the replies; from it, who came, their hours, and the km
  their travel counts (#230). A chart with nothing to draw is left out, so a new
  activity shows none.
  """
  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Trip
  alias App.Repo
  alias App.Report
  alias App.Report.Context
  alias App.ViewData.ReportRecords
  alias Service.Format

  @doc """
  The stat boxes, as `%{id:, value:, label:}`. `counts` is ActivityMembers.counts/1's,
  `attendances` the attended rows, and `km` the km of the activity's trips.
  """
  def stats(%{coming?: true, counts: counts}) do
    [
      stat("stat-signed-up", Format.number(counts.attending), "Signed up"),
      stat("stat-cant-make-it", Format.number(counts.absent), "Can't make it"),
      stat("stat-no-reply", Format.number(counts.requested), "No reply")
    ]
  end

  def stats(%{attendances: attendances, km: km}) do
    minutes = attendances |> Enum.map(& &1.duration_in_minutes) |> Enum.sum()
    members = attendances |> Enum.map(& &1.member_id) |> Enum.uniq() |> length()

    [
      stat("stat-attended", Format.number(members), "Members attended"),
      stat("stat-hours", Format.hours(minutes), "Member hours"),
      stat("stat-km", Format.number(km), "Km driven")
    ]
  end

  defp stat(id, value, label), do: %{id: id, value: value, label: label}

  @doc "The km of the activity's trips, set on Travel."
  def km(%Activity{} = activity) do
    query =
      from(t in Trip,
        where: t.team_id == ^activity.team_id and t.activity_id == ^activity.id,
        select: coalesce(sum(t.km), 0)
      )

    Repo.one(query)
  end

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
