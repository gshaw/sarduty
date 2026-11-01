defmodule App.Report.Context do
  @moduledoc """
  What a report runs against: the team, the time it runs, and the team's settings its
  fields read, such as its hours tags.
  """

  alias App.Model.Activity
  alias App.Model.Team

  defstruct [:team, :now, :timezone, :today, :hours_tags]

  def new(%Team{} = team, %DateTime{} = now) do
    now = DateTime.truncate(now, :second)

    %__MODULE__{
      team: team,
      now: now,
      timezone: team.timezone,
      today: Service.Period.today(now, team.timezone),
      hours_tags: Activity.hours_tags(team)
    }
  end
end
