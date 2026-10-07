defmodule App.MCP.Tool.ActivityHistory do
  @moduledoc """
  An activity's history (#216): its own changes and its attendance's, from
  App.ViewData.ChangeHistory. No account emails.
  """
  @behaviour App.MCP.Tool

  alias App.MCP.Tool.HistoryOutput
  alias App.Model.Activity
  alias App.Model.Team
  alias App.Repo
  alias App.ViewData.ChangeHistory

  @impl App.MCP.Tool
  def name, do: "activity_history"

  @impl App.MCP.Tool
  def description do
    "What changed on one activity, newest first, up to 200 changes: its title, times, " <>
      "tags, and published state, and its attendance. Each change says whether SAR Duty " <>
      "sent it to D4H or the refresh saw it in D4H. Get activity ids from list_activities."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "activity_id" => %{"type" => "integer", "description" => "SAR Duty's activity id"}
      },
      "required" => ["activity_id"]
    }
  end

  @impl App.MCP.Tool
  def fields, do: HistoryOutput.fields()

  @impl App.MCP.Tool
  def call(%Team{} = team, args, _now) do
    case Repo.get_by(Activity, id: args["activity_id"], team_id: team.id) do
      %Activity{} = activity ->
        entries =
          team |> ChangeHistory.for_activity(activity) |> HistoryOutput.build(team.timezone)

        {:ok, entries, length(entries)}

      nil ->
        {:error, "No activity #{inspect(args["activity_id"])} on this team."}
    end
  end
end
