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

  `hours_for` is `{member_id, year}` when only that member's year of `tax_credit_hours`
  is read, as a tax credit letter's report reads it (#918), so it doesn't count the
  whole team's every year, or `{member_ids, year}` for many letters read at once (#995).
  `tax_credit_hours` holds those counted rows, counted once when the context is made, so
  each letter's report reads them without counting again. Nil counts them all, when a
  report reads them.
  """

  import Ecto.Query, only: [where: 3]

  alias App.Model.Activity
  alias App.Model.Group
  alias App.Model.Team
  alias App.Operation.CountTaxCreditHours
  alias App.Report.Catalog
  alias App.Report.CustomFields

  defstruct [
    :team,
    :now,
    :timezone,
    :today,
    :hours_tags,
    :years,
    :tags,
    :groups,
    # The moment the query's own dates read (#826): now, or a year back for compare year.
    # Fields' rules, such as Attended and Not retired, read `now` either way.
    :dates_now,
    :dates_today,
    custom_fields: %{},
    hours_for: nil,
    tax_credit_hours: nil,
    repo: App.Repo,
    team_admin?: true
  ]

  def new(%Team{} = team, %DateTime{} = now, opts \\ []) do
    now = DateTime.truncate(now, :second)
    repo = Keyword.get(opts, :repo, App.Repo)
    activities = where(Activity, [a], a.team_id == ^team.id and is_nil(a.deleted_at))

    %__MODULE__{
      team: team,
      now: now,
      dates_now: now,
      dates_today: Service.Period.today(now, team.timezone),
      timezone: team.timezone,
      today: Service.Period.today(now, team.timezone),
      hours_tags: Activity.hours_tags(team, repo),
      years: Activity.years(activities, team.timezone, repo),
      tags: Catalog.read_tag_titles(team, repo),
      groups: Group.kinds(team, repo),
      custom_fields: CustomFields.read(team, repo),
      repo: repo,
      hours_for: Keyword.get(opts, :hours_for),
      tax_credit_hours: counted_hours(team, now, repo, Keyword.get(opts, :hours_for)),
      team_admin?: Keyword.get(opts, :team_admin?, true)
    }
  end

  defp counted_hours(_team, _now, _repo, nil), do: nil
  defp counted_hours(team, now, repo, only), do: CountTaxCreditHours.by_year(team, now, repo, only)

  @doc "The same context with the query's own dates a year back, for compare year (#826)."
  def year_back(%__MODULE__{} = context) do
    dates_now = DateTime.shift(context.now, year: -1)

    %{
      context
      | dates_now: dates_now,
        dates_today: Service.Period.today(dates_now, context.timezone)
    }
  end
end
