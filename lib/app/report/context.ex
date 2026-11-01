defmodule App.Report.Context do
  @moduledoc """
  What a report runs against: the team, the time it runs, and the team's settings its
  fields read, such as its hours tags. `years` are the years with activities, newest
  first, read once for every `:year` value a page compiles (#784).
  """

  import Ecto.Query, only: [where: 3]

  alias App.Model.Activity
  alias App.Model.Team

  defstruct [:team, :now, :timezone, :today, :hours_tags, :years]

  def new(%Team{} = team, %DateTime{} = now) do
    now = DateTime.truncate(now, :second)
    activities = where(Activity, [a], a.team_id == ^team.id and is_nil(a.deleted_at))

    %__MODULE__{
      team: team,
      now: now,
      timezone: team.timezone,
      today: Service.Period.today(now, team.timezone),
      hours_tags: Activity.hours_tags(team),
      years: Activity.years(activities, team.timezone)
    }
  end
end
