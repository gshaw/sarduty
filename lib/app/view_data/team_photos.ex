defmodule App.ViewData.TeamPhotos do
  @moduledoc """
  What Photos shows of the team's activity photos (#1033): Best of a year, Activities,
  Your stars, and Yours, each with its count. Every photo comes with its activity, its
  stars, and whether the person looking starred it. Never who else did.

  `best_of/3` is Best of the year's rule, pure. The rest read: an accepted photo is
  everyone's on the team, and a waiting one shows only under Yours, to who added it.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.ActivityPhoto
  alias App.Model.Team
  alias App.Repo
  alias Service.YearRange

  @best 24

  @doc "How many photos Best of the year holds."
  def best_limit, do: @best

  @doc """
  Pure. Best of `year`: of `photos`, each with its `stars` and its `activity`, the ones
  with a star whose activity started that year in `timezone`, the most stars first, the
  newest photo first among equals, and #{@best} at most.
  """
  def best_of(photos, year, timezone) when is_integer(year) do
    {from, to} = YearRange.bounds(year, timezone)

    photos
    |> Enum.filter(&(&1.stars > 0 and within?(&1.activity.started_at, from, to)))
    |> ActivityPhoto.by_stars()
    |> Enum.take(@best)
  end

  defp within?(at, from, to),
    do: DateTime.compare(at, from) != :lt and DateTime.before?(at, to)

  @doc "Best of `year` for the team, as `user` sees it: best_of/3 over the year's photos."
  def best(%Team{} = team, %User{} = user, year) do
    {from, to} = YearRange.bounds(year, team.timezone)

    team
    |> ActivityPhoto.accepted_query()
    |> where([activity: a], a.started_at >= ^from and a.started_at < ^to)
    |> with_activity()
    |> Repo.all()
    |> ActivityPhoto.put_stars(user)
    |> best_of(year, team.timezone)
  end

  @doc "A page of every accepted photo, newest first: Activities."
  def activities(%Team{} = team, %User{} = user, page),
    do: team |> ActivityPhoto.accepted_query() |> page(user, page)

  @doc "A page of the accepted photos `user` starred, newest first: Your stars."
  def starred(%Team{} = team, %User{} = user, page),
    do: team |> ActivityPhoto.starred_query(user) |> page(user, page)

  @doc """
  A page of the photos someone added, waiting ones included, newest first: Yours.
  `who` is ActivityPhoto.added_query/2's.
  """
  def added(%Team{} = team, who, %User{} = user, page),
    do: team |> ActivityPhoto.added_query(who) |> page(user, page)

  defp page(query, user, page) do
    paginated =
      query
      |> order_by([p], desc: p.inserted_at, desc: p.id)
      |> with_activity()
      |> Repo.paginate(page: page)

    %{paginated | entries: ActivityPhoto.put_stars(paginated.entries, user)}
  end

  defp with_activity(query), do: preload(query, [activity: a], activity: a)

  @doc """
  The counts on Photos' tiles, but Best of's, which is the length of its list:
  `%{activities:, stars:, yours:}`.
  """
  def counts(%Team{} = team, %User{} = user, who) do
    %{
      activities: team |> ActivityPhoto.accepted_query() |> count(),
      stars: team |> ActivityPhoto.starred_query(user) |> count(),
      yours: team |> ActivityPhoto.added_query(who) |> count()
    }
  end

  defp count(query), do: Repo.aggregate(query, :count)

  @doc "Whether the team has an accepted photo: Photos then opens on Best of the year."
  def any?(%Team{} = team), do: team |> ActivityPhoto.accepted_query() |> Repo.exists?()

  @doc """
  The years Best of offers, newest first: from the first activity with an accepted
  photo to this year, in the team's time zone. This year alone when there are none.
  """
  def years(%Team{} = team, %DateTime{} = now) do
    first =
      team
      |> ActivityPhoto.accepted_query()
      |> select([activity: a], min(a.started_at))
      |> Repo.one()

    # An activity moved to next year after its photos were added still leaves this year.
    [first || now, now] |> Enum.min(DateTime) |> YearRange.years(now, team.timezone)
  end
end
