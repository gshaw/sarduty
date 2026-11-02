defmodule App.Report.Context do
  @moduledoc """
  What a report runs against: the team, the time it runs, who reads it, and the team's
  settings its fields read, such as its hours tags. `years` are the years with
  activities, newest first, `tags` the tags' titles as choices, and `groups` the groups
  as `{title, id}`: each read once for the many queries a page compiles (#784).

  `team_admin?` is false for a member reading a list such as Members (#784): the catalog
  hides what only team admins see, and a page's options that read it drop out.

  `repo` is the database every read goes to: App.Repo, or App.SampleRepo for Coast Range
  SAR (#816). Nothing in a run reads another.
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
    # Experiment (charts): the moment the query's own dates read, a year back for
    # `compare year`. Fields' rules, such as status and standing, read `now`.
    :dates_now,
    :dates_today,
    repo: App.Repo,
    team_admin?: true
  ]

  def new(%Team{} = team, %DateTime{} = now, opts \\ []) do
    now = DateTime.truncate(now, :second)
    repo = Keyword.get(opts, :repo, App.Repo)
    activities = where(Activity, [a], a.team_id == ^team.id and is_nil(a.deleted_at))

    dates_now = DateTime.shift(now, year: -Keyword.get(opts, :dates_back, 0))

    %__MODULE__{
      team: team,
      now: now,
      dates_now: dates_now,
      dates_today: Service.Period.today(dates_now, team.timezone),
      timezone: team.timezone,
      today: Service.Period.today(now, team.timezone),
      hours_tags: Activity.hours_tags(team, repo),
      years: Activity.years(activities, team.timezone, repo),
      tags: Catalog.read_tag_titles(team, repo),
      groups: Group.kinds(team, repo),
      repo: repo,
      team_admin?: Keyword.get(opts, :team_admin?, true)
    }
  end
end
