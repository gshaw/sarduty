defmodule App.MCP.Tool.ProposeAttendanceChanges do
  @moduledoc """
  Drafts attendance changes for one activity as a change set that waits for a team admin
  (#216). Nothing reaches D4H until a person reviews and sends it in SAR Duty.
  """
  @behaviour App.MCP.Tool

  alias App.Model.Team
  alias App.Operation.ProposeAttendanceChanges

  @max_changes 200

  @impl App.MCP.Tool
  def name, do: "propose_attendance_changes"

  @impl App.MCP.Tool
  def description do
    "Proposes attendance changes for one activity, such as from a paper sign-in sheet, " <>
      "members to add, or a duplicate row. Nothing changes until a team admin sends it in " <>
      "SAR Duty. Name a row by its attendance_id from list_attendance, or give a member_id " <>
      "to add one. Before the activity starts, status is no_reply, signed_up, or " <>
      "cant_make_it. Once it starts, status is attended or absent. remove takes a row off " <>
      "at any time. Give optional start and end times as ISO 8601 with an offset; a row " <>
      "added without times gets the activity's. Give a short reason per change, such as " <>
      "the sheet row, and a one-line summary. Returns the link for the team admin and any " <>
      "changes left out, with why. A published activity is made a draft for the change, " <>
      "then published again. Deleted and chore activities cannot change."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "activity_id" => %{"type" => "integer", "description" => "SAR Duty's activity id"},
        "summary" => %{
          "type" => "string",
          "description" => "One line for the team admin, such as Sign-in sheet for Oct 3"
        },
        "changes" => %{
          "type" => "array",
          "maxItems" => @max_changes,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "attendance_id" => %{"type" => "integer"},
              "member_id" => %{"type" => "integer"},
              "status" => %{
                "type" => "string",
                "enum" => ~w(no_reply signed_up cant_make_it attended absent remove)
              },
              "starts_at" => %{"type" => "string", "format" => "date-time"},
              "ends_at" => %{"type" => "string", "format" => "date-time"},
              "reason" => %{"type" => "string"}
            },
            "required" => ["status"]
          }
        }
      },
      "required" => ["activity_id", "summary", "changes"]
    }
  end

  @impl App.MCP.Tool
  def fields, do: ~w(change_set_id review_url proposed left_out)

  @impl App.MCP.Tool
  def read_only?, do: false

  @impl App.MCP.Tool
  def call_as(%Team{} = team, user, args, now) do
    changes = args["changes"]

    cond do
      not is_list(changes) or changes == [] ->
        {:error, "Give changes as a list of 1 or more."}

      length(changes) > @max_changes ->
        {:error, "Give at most #{@max_changes} changes at once."}

      not Enum.all?(changes, &is_map/1) ->
        {:error, "Give each change as an object."}

      true ->
        propose(team, user, args["activity_id"], changes, args["summary"], now)
    end
  end

  defp propose(team, user, activity_id, changes, summary, now) do
    summary = if is_binary(summary), do: summary

    case ProposeAttendanceChanges.call(team, user, activity_id, changes, summary, now) do
      {:ok, change_set, problems} ->
        output = %{
          "change_set_id" => change_set.id,
          "review_url" =>
            "#{Web.Endpoint.url()}/teams/#{team.subdomain}/proposed-changes/#{change_set.id}",
          "proposed" => length(change_set.rows),
          "left_out" => problems
        }

        {:ok, output, length(change_set.rows)}

      {:error, problems} ->
        {:error, "Nothing to propose. " <> Enum.join(problems, " ")}
    end
  end
end
