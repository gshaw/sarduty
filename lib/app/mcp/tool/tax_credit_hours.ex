defmodule App.MCP.Tool.TaxCreditHours do
  @moduledoc """
  Each member's hours for one year as a tax credit letter counts them (#595), with
  `CountTaxCreditHours`, so they always agree with the letters page. Never a letter's text.
  """
  @behaviour App.MCP.Tool

  import Ecto.Query

  alias App.MCP.Output
  alias App.Model.Member
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Operation.CountTaxCreditHours
  alias App.Repo

  @impl App.MCP.Tool
  def name, do: "tax_credit_hours"

  @impl App.MCP.Tool
  def description do
    "Each member's hours for one year as a tax credit letter counts them: primary, " <>
      "secondary, and total. Time spent at two activities at once counts once, and chores " <>
      "are added up, so these can be lower than attendance_summary. letter_made_on is the " <>
      "date the member's letter for that year was made, or null. Lists every member on the " <>
      "team during the year. Give member_id for one member."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "year" => %{"type" => "integer", "description" => "The tax year, such as 2026"},
        "member_id" => %{"type" => "integer", "description" => "SAR Duty's member id"}
      },
      "required" => ["year"]
    }
  end

  @impl App.MCP.Tool
  def fields do
    ~w(year members member_id name primary_hours secondary_hours total_hours letter_made_on)
  end

  @impl App.MCP.Tool
  def call(%Team{} = team, args, now) do
    with {:ok, year} <- year(args["year"]),
         {:ok, member_ids} <- member_ids(team, args["member_id"]) do
      hours = CountTaxCreditHours.call(team, year, member_ids, now)
      members = load_members(team, member_ids)
      letters = load_letters(team, year, member_ids)
      bounds = Service.YearRange.bounds(year, team.timezone)

      output = %{
        "year" => year,
        "members" => build(members, hours, letters, bounds, team.timezone)
      }

      {:ok, output, length(output["members"])}
    end
  end

  defp year(year) when is_integer(year) and year in 2000..2100, do: {:ok, year}
  defp year(_year), do: {:error, "Give year as a number, such as 2026."}

  defp member_ids(_team, nil), do: {:ok, nil}

  defp member_ids(team, id) do
    if is_integer(id) and Repo.get_by(Member, id: id, team_id: team.id),
      do: {:ok, [id]},
      else: {:error, "No member #{inspect(id)} on this team."}
  end

  @doc """
  One entry per member, by name: those on the team at some point in the year's `bounds`
  (`{start, finish}`, UTC), and anyone with hours. `hours` is `CountTaxCreditHours`'s,
  by member id, and `letters` the date each member's letter was made, by member id.
  """
  def build(members, hours, letters, {start, finish}, timezone) do
    members
    |> Enum.filter(&(on_team?(&1, start, finish) or Map.has_key?(hours, &1.id)))
    |> Enum.sort_by(&{&1.name, &1.id})
    |> Enum.map(fn member ->
      counted = CountTaxCreditHours.get(hours, member.id)

      %{
        "member_id" => member.id,
        "name" => member.name,
        "primary_hours" => Output.hours(counted.primary_minutes),
        "secondary_hours" => Output.hours(counted.secondary_minutes),
        "total_hours" => Output.hours(counted.total_minutes),
        "letter_made_on" => letter_date(Map.get(letters, member.id), timezone)
      }
    end)
  end

  defp letter_date(nil, _timezone), do: nil

  defp letter_date(made_at, timezone),
    do: made_at |> Service.Period.today(timezone) |> Date.to_iso8601()

  defp on_team?(member, start, finish) do
    (is_nil(member.joined_at) or DateTime.before?(member.joined_at, finish)) and
      (is_nil(member.left_at) or DateTime.after?(member.left_at, start))
  end

  defp load_members(team, member_ids) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> scope(member_ids)
    |> select([m], map(m, [:id, :name, :joined_at, :left_at]))
    |> Repo.all()
  end

  defp load_letters(team, year, member_ids) do
    TaxCreditLetter
    |> join(:inner, [l], m in Member, on: m.id == l.member_id)
    |> where([l, m], m.team_id == ^team.id and l.year == ^year)
    |> scope_letters(member_ids)
    |> group_by([l], l.member_id)
    |> select([l], {l.member_id, type(max(l.inserted_at), :utc_datetime_usec)})
    |> Repo.all()
    |> Map.new()
  end

  defp scope(query, nil), do: query
  defp scope(query, ids), do: where(query, [m], m.id in ^ids)

  defp scope_letters(query, nil), do: query
  defp scope_letters(query, ids), do: where(query, [l], l.member_id in ^ids)
end
