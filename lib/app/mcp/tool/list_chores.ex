defmodule App.MCP.Tool.ListChores do
  @moduledoc """
  The team's chores done in a date range (#595), with what the member wrote they did. A
  decline's reason, a message to the member, and who decided are left out.
  """
  @behaviour App.MCP.Tool

  import Ecto.Query

  alias App.MCP.Args
  alias App.Model.Activity
  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Model.Team
  alias App.Repo

  @statuses %{"waiting" => :waiting, "accepted" => :accepted, "declined" => :declined}

  @impl App.MCP.Tool
  def name, do: "list_chores"

  @impl App.MCP.Tool
  def description do
    "The team's chores done from one date to another, both included, in the team's time " <>
      "zone, oldest first. Each has its id, member id and name, chore category id and " <>
      "title, hours (primary or secondary), date, and minutes. It also has what they did, " <>
      "and its status: waiting, accepted, or declined. activity_id is its chore " <>
      "activity once sent and refreshed. Give status or member_id to list fewer. Empty " <>
      "when the team has chores off."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "from" => %{"type" => "string", "format" => "date", "description" => "First day"},
        "to" => %{"type" => "string", "format" => "date", "description" => "Last day"},
        "status" => %{"type" => "string", "enum" => Map.keys(@statuses)},
        "member_id" => %{"type" => "integer", "description" => "SAR Duty's member id"}
      },
      "required" => ["from", "to"]
    }
  end

  @impl App.MCP.Tool
  def fields do
    ~w(id member_id member_name chore_category_id category hours date minutes what_they_did
       status activity_id)
  end

  @impl App.MCP.Tool
  def call(%Team{} = team, args, _now) do
    with {:ok, from, to, _start, _finish} <- Args.date_range(args, team.timezone),
         {:ok, status} <- status_arg(args) do
      chores = load(team, from, to, status, args["member_id"])
      output = build(chores, activity_ids(team, chores))
      {:ok, output, length(output)}
    end
  end

  defp status_arg(args) do
    case Args.optional_string(args, "status") do
      nil ->
        {:ok, nil}

      status ->
        case Map.fetch(@statuses, status) do
          {:ok, status} -> {:ok, status}
          :error -> {:error, "Give status as waiting, accepted, or declined."}
        end
    end
  end

  @doc """
  The output for `chores`, with their members, categories, and events, oldest first.
  `activity_ids` maps a chore event's D4H activity id to the local activity's id.
  """
  def build(chores, activity_ids) do
    chores
    |> Enum.sort_by(&{Date.to_gregorian_days(&1.date), &1.id})
    |> Enum.map(fn chore ->
      %{
        "id" => chore.id,
        "member_id" => chore.member_id,
        "member_name" => chore.member.name,
        "chore_category_id" => chore.chore_category_id,
        "category" => chore.chore_category.title,
        "hours" => Atom.to_string(chore.chore_category.hours),
        "date" => Date.to_iso8601(chore.date),
        "minutes" => chore.minutes,
        "what_they_did" => chore.description,
        "status" => Atom.to_string(chore.status),
        "activity_id" => activity_id(chore, activity_ids)
      }
    end)
  end

  defp activity_id(%{status: :accepted, chore_event: %ChoreEvent{d4h_activity_id: id}}, ids)
       when is_integer(id),
       do: Map.get(ids, id)

  defp activity_id(_chore, _ids), do: nil

  defp load(team, from, to, status, member_id) do
    if Team.chores?(team) do
      Chore
      |> where([c], c.team_id == ^team.id and c.date >= ^from and c.date <= ^to)
      |> then(&if status, do: where(&1, [c], c.status == ^status), else: &1)
      |> then(&if is_integer(member_id), do: where(&1, [c], c.member_id == ^member_id), else: &1)
      |> preload([:member, :chore_category, :chore_event])
      |> Repo.all()
    else
      []
    end
  end

  defp activity_ids(team, chores) do
    d4h_ids =
      for %{chore_event: %ChoreEvent{d4h_activity_id: id}} <- chores, is_integer(id), do: id

    Activity
    |> where([a], a.team_id == ^team.id and a.d4h_activity_id in ^Enum.uniq(d4h_ids))
    |> select([a], {a.d4h_activity_id, a.id})
    |> Repo.all()
    |> Map.new()
  end
end
