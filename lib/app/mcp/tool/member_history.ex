defmodule App.MCP.Tool.MemberHistory do
  @moduledoc """
  A member's history (#216): what SAR Duty changed in D4H and what the refresh saw change
  there, from App.ViewData.ChangeHistory. No contact details, and no account emails.
  """
  @behaviour App.MCP.Tool

  alias App.MCP.Tool.HistoryOutput
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo
  alias App.ViewData.ChangeHistory

  @impl App.MCP.Tool
  def name, do: "member_history"

  @impl App.MCP.Tool
  def description do
    "What changed for one member, newest first, up to 200 changes: attendance, " <>
      "qualifications, groups, and their D4H record. Each change says whether SAR Duty " <>
      "sent it to D4H or the refresh saw it in D4H. D4H does not say who made a change " <>
      "there, so those give the window between 2 refreshes. Contact details changes are " <>
      "named without values. Get member ids from list_members."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "member_id" => %{"type" => "integer", "description" => "SAR Duty's member id"}
      },
      "required" => ["member_id"]
    }
  end

  @impl App.MCP.Tool
  def fields, do: HistoryOutput.fields()

  @impl App.MCP.Tool
  def call(%Team{} = team, args, _now) do
    case Repo.get_by(Member, id: args["member_id"], team_id: team.id) do
      %Member{} = member ->
        entries = team |> ChangeHistory.for_member(member) |> HistoryOutput.build(team.timezone)
        {:ok, entries, length(entries)}

      nil ->
        {:error, "No member #{inspect(args["member_id"])} on this team."}
    end
  end
end
