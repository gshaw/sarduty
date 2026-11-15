defmodule App.MCP.Tool.ListForms do
  @moduledoc """
  The team's own forms (#1083): each one's id, name, description, whether it's off,
  testing, or on, its version, whether it's written yet, and how many pages its PDF has.
  A form is how the team is organized, like a report's query: never a filled-in copy.
  """
  @behaviour App.MCP.Tool

  alias App.MCP.Tool.ReadForm
  alias App.Model.Form
  alias App.Model.Team

  @impl App.MCP.Tool
  def name, do: "list_forms"

  @impl App.MCP.Tool
  def description do
    "Start here for forms. The team's own forms, each with its id, name, description, " <>
      "state (off, testing, or on), version, whether it's written yet, and how many " <>
      "pages its PDF has. A team admin starts a form in SAR Duty from the agency's PDF; " <>
      "you write its text with read_form and check_form, and they save it there."
  end

  @impl App.MCP.Tool
  def input_schema, do: %{"type" => "object", "properties" => %{}}

  @impl App.MCP.Tool
  def fields, do: ~w(forms id name description state version written pages)

  @impl App.MCP.Tool
  def call(%Team{} = team, _args, _now, _connection) do
    with :ok <- ReadForm.check_on(team) do
      forms = Form.get_all(team)
      {:ok, build(forms, Map.new(forms, &{&1.id, pages(&1)})), length(forms)}
    end
  end

  defp pages(form) do
    with bytes when is_binary(bytes) <- Form.page_bytes(form),
         {:ok, count} <- Service.PDFPages.count(bytes) do
      count
    else
      _none -> 0
    end
  end

  @doc "The output, from the team's forms and each one's page count."
  def build(forms, pages) do
    %{
      "forms" =>
        Enum.map(forms, fn form ->
          %{
            "id" => form.id,
            "name" => form.name,
            "description" => form.about,
            "state" => Atom.to_string(form.state),
            "version" => form.version,
            "written" => Form.written?(form),
            "pages" => pages[form.id]
          }
        end)
    }
  end
end
