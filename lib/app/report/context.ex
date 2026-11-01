defmodule App.Report.Context do
  @moduledoc """
  What a report runs against: the team, the time it runs, who reads it, and the team's
  settings its fields read, such as its hours tags. `years` are the years with
  activities, newest first, read once for every `:year` value a page compiles (#784).

  `team_admin?` is false for a member reading a list such as Members (#784): the catalog
  hides what only team admins see, and a page's options that read it drop out.
  """

  import Ecto.Query, only: [where: 3]

  alias App.Model.Activity
  alias App.Model.Team

  defstruct [:team, :now, :timezone, :today, :hours_tags, :years, team_admin?: true]

  def new(%Team{} = team, %DateTime{} = now, opts \\ []) do
    now = DateTime.truncate(now, :second)
    activities = where(Activity, [a], a.team_id == ^team.id and is_nil(a.deleted_at))

    %__MODULE__{
      team: team,
      now: now,
      timezone: team.timezone,
      today: Service.Period.today(now, team.timezone),
      hours_tags: Activity.hours_tags(team),
      years: Activity.years(activities, team.timezone),
      team_admin?: Keyword.get(opts, :team_admin?, true)
    }
  end
end
