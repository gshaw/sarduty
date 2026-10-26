defmodule App.MCP.Tool.ProposeChores do
  @moduledoc """
  Drafts chores for members as one change set that waits for a team admin (#595). Nothing
  is added until a person accepts them in SAR Duty; accepting sends them.
  """
  @behaviour App.MCP.Tool

  alias App.Model.Team
  alias App.Operation.ProposeChores

  @max_chores 200

  @impl App.MCP.Tool
  def name, do: "propose_chores"

  @impl App.MCP.Tool
  def description do
    "Proposes chores for members, such as from a work party's sign-in sheet or a board " <>
      "meeting's minutes. Nothing is added until a team admin accepts them in SAR Duty. " <>
      "Accepting sends them. For each chore, give the member id, chore category id (from " <>
      "get_team), date, minutes, what they did, and a short reason. The date is YYYY-MM-DD " <>
      "and not in the future, minutes are 1 to 1440, and what they did is up to 200 " <>
      "characters. Give a one-line summary too. Returns the link for the team admin, " <>
      "chores left out with why, and chores to check, which start cleared."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "summary" => %{
          "type" => "string",
          "description" => "One line for the team admin, such as Work party, Oct 3"
        },
        "chores" => %{
          "type" => "array",
          "maxItems" => @max_chores,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "member_id" => %{"type" => "integer"},
              "chore_category_id" => %{"type" => "integer"},
              "date" => %{"type" => "string", "format" => "date"},
              "minutes" => %{"type" => "integer"},
              "description" => %{"type" => "string"},
              "reason" => %{"type" => "string"}
            },
            "required" => ["member_id", "chore_category_id", "date", "minutes", "description"]
          }
        }
      },
      "required" => ["summary", "chores"]
    }
  end

  @impl App.MCP.Tool
  def fields, do: ~w(change_set_id review_url proposed left_out to_check)

  @impl App.MCP.Tool
  def read_only?, do: false

  @impl App.MCP.Tool
  def call_as(%Team{} = team, user, args, now) do
    chores = args["chores"]

    cond do
      not is_list(chores) or chores == [] ->
        {:error, "Give chores as a list of 1 or more."}

      length(chores) > @max_chores ->
        {:error, "Give at most #{@max_chores} chores at once."}

      not Enum.all?(chores, &is_map/1) ->
        {:error, "Give each chore as an object."}

      true ->
        summary = if is_binary(args["summary"]), do: args["summary"]
        propose(team, user, chores, summary, now)
    end
  end

  defp propose(team, user, chores, summary, now) do
    case ProposeChores.call(team, user, chores, summary, now) do
      {:ok, change_set, problems, checks} ->
        output = %{
          "change_set_id" => change_set.id,
          "review_url" =>
            "#{Web.Endpoint.url()}/teams/#{team.subdomain}/proposed-changes/#{change_set.id}",
          "proposed" => length(change_set.rows),
          "left_out" => problems,
          "to_check" => checks
        }

        {:ok, output, length(change_set.rows)}

      {:error, problems} ->
        {:error, "Nothing to propose. " <> Enum.join(problems, " ")}
    end
  end
end
