defmodule App.MCP.Tool.ProposeActivityTags do
  @moduledoc """
  Drafts tag changes on up to 50 activities as one change set that waits for a team admin
  (#595). Nothing reaches D4H until a person reviews and sends it in SAR Duty.
  """
  @behaviour App.MCP.Tool

  alias App.Model.Team
  alias App.Operation.ProposeActivityTags

  @max_changes 50

  @impl App.MCP.Tool
  def name, do: "propose_activity_tags"

  @impl App.MCP.Tool
  def description do
    "Proposes tag changes on up to 50 activities, such as adding the primary hours tag to " <>
      "activities that count no hours. Nothing changes until a team admin sends it in SAR " <>
      "Duty. For each activity, give its id, tag titles to add, tag titles to remove, and a " <>
      "short reason. Give a one-line summary too. A tag must already be on the team; " <>
      "get_team names the hours tags, and an activity cannot have both. Only draft " <>
      "activities: published and chore activities cannot change. Returns the link for " <>
      "the team admin and any changes left out, with why."
  end

  @impl App.MCP.Tool
  def input_schema do
    titles = %{"type" => "array", "items" => %{"type" => "string"}}

    %{
      "type" => "object",
      "properties" => %{
        "summary" => %{
          "type" => "string",
          "description" => "One line for the team admin, such as Hours tags for 2026"
        },
        "changes" => %{
          "type" => "array",
          "maxItems" => @max_changes,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "activity_id" => %{"type" => "integer"},
              "add" => titles,
              "remove" => titles,
              "reason" => %{"type" => "string"}
            },
            "required" => ["activity_id"]
          }
        }
      },
      "required" => ["summary", "changes"]
    }
  end

  @impl App.MCP.Tool
  def fields, do: ~w(change_set_id review_url proposed left_out)

  @impl App.MCP.Tool
  def read_only?, do: false

  @impl App.MCP.Tool
  def call_as(%Team{} = team, user, args, _now) do
    changes = args["changes"]

    cond do
      not is_list(changes) or changes == [] ->
        {:error, "Give changes as a list of 1 or more."}

      length(changes) > @max_changes ->
        {:error, "Give at most #{@max_changes} activities at once."}

      not Enum.all?(changes, &is_map/1) ->
        {:error, "Give each change as an object."}

      true ->
        summary = if is_binary(args["summary"]), do: args["summary"]
        propose(team, user, changes, summary)
    end
  end

  defp propose(team, user, changes, summary) do
    case ProposeActivityTags.call(team, user, changes, summary) do
      {:ok, change_set, problems} ->
        lines = Enum.count(change_set.rows, &(&1.action == :set_activity_tags))

        output = %{
          "change_set_id" => change_set.id,
          "review_url" =>
            "#{Web.Endpoint.url()}/teams/#{team.subdomain}/proposed-changes/#{change_set.id}",
          "proposed" => lines,
          "left_out" => problems
        }

        {:ok, output, lines}

      {:error, problems} ->
        {:error, "Nothing to propose. " <> Enum.join(problems, " ")}
    end
  end
end
