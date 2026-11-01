defmodule App.Report.Context do
  @moduledoc """
  What a report runs against: the team, the time it runs, who reads it, and the team's
  settings its fields read, such as its hours tags. `years` are the years with
  activities, newest first, `tags` the tags' titles as choices, and `groups` the groups
  as `{title, id}`: each read once for the many queries a page compiles (#784).

  `team_admin?` is false for a member reading a list such as Members (#784): the catalog
  hides what only team admins see, and a page's options that read it drop out.
  """

  import Ecto.Query, only: [where: 3]

  alias App.Model.Activity
  alias App.Model.Group
  alias App.Model.Team
  alias App.Report.Catalog

  defstruct [
    :team,
    :now,
    :timezone,
    :today,
    :hours_tags,
    :years,
    :tags,
    :groups,
    team_admin?: true
  ]

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
      tags: Catalog.read_tag_titles(team),
      groups: Group.kinds(team),
      team_admin?: Keyword.get(opts, :team_admin?, true)
    }
  end
end
