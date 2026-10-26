defmodule App.Operation.ProposeChores do
  @moduledoc """
  An AI agent's chores for members, saved as one change set that waits for a team admin
  (#595). Each chore is an `add_chore` row: SAR Duty's own, not a D4H write. Accepting the
  set makes the chores, accepted by that team admin, and the chore send takes them to D4H
  (ApplyProposedChangeSet). Members never see a proposed chore.

  plan/5 decides the rows, pure; call/5 reads and saves.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  @max_minutes 24 * 60

  @doc """
  Saves the chores as a waiting change set. `requests` are maps with string keys:
  `member_id`, `chore_category_id`, `date` (YYYY-MM-DD), `minutes`, `description`, and
  `reason`. `{:ok, change_set, problems, checks}` or `{:error, problems}`.
  """
  def call(%Team{} = team, %User{} = user, requests, summary, now) do
    if Team.chores?(team) do
      team
      |> context(requests, now)
      |> plan(requests, Service.Period.today(now, team.timezone))
      |> save(team, user, summary)
    else
      {:error, ["Chores are off for this team. A team admin turns them on in team settings."]}
    end
  end

  defp context(team, requests, now) do
    %{
      members: members(team, requests),
      categories: ChoreCategory.get_open(team.id),
      taken: taken(team),
      open_years: Service.Period.open_years(now, team.timezone)
    }
  end

  defp save({[], problems}, _team, _user, _summary), do: {:error, problems}

  defp save({rows, problems}, team, user, summary) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :agent,
          proposed_by_user_id: user.id,
          summary: summary && String.slice(summary, 0, 255)
        },
        rows
      )

    {:ok, change_set, problems, for(r <- rows, r.new_value["check"], do: r.new_value["check"])}
  end

  defp members(team, requests) do
    ids = for r <- requests, is_integer(r["member_id"]), do: r["member_id"]

    Member
    |> where([m], m.team_id == ^team.id and m.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  # Chores logged or waiting in another proposal, as {member, category, date, minutes}.
  defp taken(team) do
    logged =
      Chore
      |> where([c], c.team_id == ^team.id and c.status != :declined)
      |> select([c], {c.member_id, c.chore_category_id, c.date, c.minutes})
      |> Repo.all()

    proposed =
      for set <- ChangeSet.get_waiting(team.id),
          row <- set.rows,
          row.action == :add_chore,
          do:
            {row.member_id, row.new_value["chore_category_id"],
             Date.from_iso8601!(row.new_value["date"]), row.new_value["minutes"]}

    MapSet.new(logged ++ proposed)
  end

  @doc """
  The rows for `requests`, and a sentence for each left out. Pure. `context` has
  `members` by id, open `categories`, `taken` chores as `{member_id, category_id, date,
  minutes}`, and the `open_years`, a list. A chore matching a taken one is still proposed,
  with a `"check"` the review page shows, and starts cleared there.
  """
  def plan(context, requests, %Date{} = today) do
    categories = Map.new(context.categories, &{&1.id, &1})

    {rows, problems} =
      Enum.reduce(requests, {[], []}, fn request, {rows, problems} ->
        case plan_row(context, categories, request, today) do
          {:ok, row} -> {[row | rows], problems}
          {:problem, text} -> {rows, [text | problems]}
        end
      end)

    {Enum.reverse(rows), Enum.reverse(problems)}
  end

  defp plan_row(context, categories, request, today) do
    with {:ok, member} <- fetch(context.members, request["member_id"], "member"),
         {:ok, category} <- fetch(categories, request["chore_category_id"], "open chore category"),
         {:ok, chore} <- when_and_what(member, request, today, context.open_years) do
      {:ok, row(Map.put(chore, :category, category), context.taken, reason(request))}
    end
  end

  # The chore's date, minutes, and what they did, checked.
  defp when_and_what(member, request, today, open_years) do
    with {:ok, date} <- date(request["date"], today, open_years),
         :ok <- on_team(member, date),
         {:ok, minutes} <- minutes(request["minutes"]),
         {:ok, description} <- description(request["description"]),
         do: {:ok, %{member: member, date: date, minutes: minutes, description: description}}
  end

  defp row(chore, taken, reason) do
    taken? =
      MapSet.member?(taken, {chore.member.id, chore.category.id, chore.date, chore.minutes})

    %ChangeSetRow{
      member_id: chore.member.id,
      action: :add_chore,
      new_value: %{
        "chore_category_id" => chore.category.id,
        "category" => chore.category.title,
        "date" => Date.to_iso8601(chore.date),
        "minutes" => chore.minutes,
        "description" => chore.description,
        "check" => if(taken?, do: duplicate(chore))
      },
      reason: reason
    }
  end

  defp fetch(map, id, noun) do
    case is_integer(id) && Map.get(map, id) do
      found when is_map(found) -> {:ok, found}
      _none -> {:problem, "No #{noun} #{inspect(id)} on this team."}
    end
  end

  defp date(text, today, open_years) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} ->
        cond do
          Date.after?(date, today) ->
            {:problem, "#{text} is in the future. Give a date that has passed."}

          date.year not in open_years ->
            {:problem,
             "#{text} is not in an open year. Give a date in #{Enum.join(open_years, " or ")}."}

          true ->
            {:ok, date}
        end

      {:error, _} ->
        {:problem, "Give date as YYYY-MM-DD, not #{inspect(text)}."}
    end
  end

  defp date(other, _today, _open_years),
    do: {:problem, "Give date as YYYY-MM-DD, not #{inspect(other)}."}

  defp on_team(member, date) do
    left_on = member.left_at && DateTime.to_date(member.left_at)

    if left_on && Date.after?(date, left_on),
      do: {:problem, "#{member.name} left the team before #{Date.to_iso8601(date)}."},
      else: :ok
  end

  defp minutes(minutes) when is_integer(minutes) and minutes in 1..@max_minutes,
    do: {:ok, minutes}

  defp minutes(minutes),
    do: {:problem, "Give minutes from 1 to #{@max_minutes}, not #{inspect(minutes)}."}

  defp description(text) when is_binary(text) do
    case String.trim(text) do
      "" -> {:problem, "Give what they did for each chore."}
      text -> {:ok, String.slice(text, 0, 200)}
    end
  end

  defp description(_other), do: {:problem, "Give what they did for each chore."}

  defp duplicate(chore),
    do:
      "#{chore.member.name} already has #{Service.Format.duration(chore.minutes)} of " <>
        "#{chore.category.title} on #{Service.Format.date_short(chore.date)}."

  defp reason(%{"reason" => reason}) when is_binary(reason) and reason != "",
    do: String.slice(reason, 0, 255)

  defp reason(_request), do: "Proposed by an AI agent"
end
