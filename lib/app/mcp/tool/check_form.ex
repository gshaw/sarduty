defmodule App.MCP.Tool.CheckForm do
  @moduledoc """
  Checks an agent's text for one of the team's own forms (#1083), as saving would, and
  gives the link a team admin opens to try it and save it. Saves nothing: a text that
  passes is the user's draft (App.Document.Draft), shown on their Change page as it
  arrives, until they save it or a day passes.

  The checks are SaveForm's: the text against the team's fields, every `expect`, every
  place on a page of the form's PDF, and its name. None reads the team's records, so
  the reply never says anything about them.
  """
  @behaviour App.MCP.Tool

  use Web, :verified_routes

  alias App.Document.Draft
  alias App.MCP.Tool.ReadForm
  alias App.Model.AgentConnection
  alias App.Model.Form
  alias App.Model.Team
  alias App.Operation.SaveForm

  @impl App.MCP.Tool
  def name, do: "check_form"

  @impl App.MCP.Tool
  def description do
    "Check a form's whole text as saving would: against this team's fields, its expect " <>
      "lines, and its page. A mistake names its line. A text that passes goes to the team " <>
      "admin's Change page, where they try it on an activity and save it: give them the " <>
      "link once, and each later check shows there. Send the whole text each time, with a " <>
      "line on what changed."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "form_id" => %{"type" => "integer", "description" => "The form's id, from list_forms"},
        "text" => %{"type" => "string", "description" => "The form's whole text"},
        "change" => %{
          "type" => "string",
          "description" => "One line on what this text changes, 100 characters at most"
        }
      },
      "required" => ["form_id", "text"]
    }
  end

  @impl App.MCP.Tool
  def fields, do: ~w(ok name version link)

  @impl App.MCP.Tool
  def call(%Team{} = team, args, now, %AgentConnection{} = connection) do
    with {:ok, form} <- ReadForm.form(team, args["form_id"]),
         {:ok, text} <- text(args["text"]),
         {:ok, doc} <- check(team, form, text, now) do
      Draft.put(team, connection.user_id, form, draft(text, args, connection, now))
      {:ok, build(doc.name, SaveForm.next_version(form), link(team, form)), 1}
    end
  end

  defp draft(text, args, connection, now),
    do: %Draft{text: text, change: change(args["change"]), agent: connection.name, at: now}

  defp text(text) when is_binary(text) and text != "", do: {:ok, text}
  defp text(_text), do: {:error, "Give text as the form's whole text."}

  defp change(change) when is_binary(change) and change != "", do: String.slice(change, 0, 100)
  defp change(_change), do: nil

  defp check(team, form, text, now) do
    case SaveForm.check_for(team, form, text, Form.page_bytes(form), now) do
      {:ok, doc} -> {:ok, doc}
      {:error, _field, message} -> {:error, message}
    end
  end

  @doc "The output: the form's name and the version it saves as, and the link."
  def build(name, version, link),
    do: %{"ok" => true, "name" => name, "version" => version, "link" => link}

  @doc "The form's Change page, where the team admin tries the draft and saves it."
  def link(team, form), do: url(~p"/teams/#{team}/settings/forms/#{form}/edit")
end
