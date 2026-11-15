defmodule App.MCP.Tool.ReadForm do
  @moduledoc """
  One of the team's own forms (#1083), for an agent writing it: the form language, the
  form's text, and what's printed where on its page, from Service.PDFGeometry. The page
  is the agency's blank form a team admin gave SAR Duty, never a filled-in copy. The AI
  reads the labels; the points come from the PDF, so a place is measured, not guessed.
  """
  @behaviour App.MCP.Tool

  alias App.Model.Form
  alias App.Model.Team

  # The form language: docs/documents.md, built in so it can't drift from the docs.
  @language_path Path.expand("../../../../docs/documents.md", __DIR__)
  @external_resource @language_path
  @language File.read!(@language_path)

  @impl App.MCP.Tool
  def name, do: "read_form"

  @impl App.MCP.Tool
  def description do
    "One of the team's forms, to write or change it: the form language (read Forms and " <>
      "Preparing a form), its text (empty until it's written), and its PDF's pages. Each " <>
      "page lists its lines of text, blanks (runs of underscores), rules (drawn lines), and " <>
      "boxes, in points from the page's top left. Write each place from those numbers, as " <>
      "Preparing a form says. A form reads the team's fields with report queries: " <>
      "report_fields has that language and the team's fields. Then check it with check_form."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "form_id" => %{"type" => "integer", "description" => "The form's id, from list_forms"}
      },
      "required" => ["form_id"]
    }
  end

  @impl App.MCP.Tool
  def fields,
    do: ~w(name state version text language pages page width height lines blanks rules boxes
         x0 x1 top bottom baseline size y)

  @impl App.MCP.Tool
  def call(%Team{} = team, args, _now, _connection) do
    with {:ok, form} <- form(team, args["form_id"]),
         {:ok, pages} <- pages(form) do
      {:ok, build(form, pages), 1}
    end
  end

  @doc "`:ok`, or the error an agent gets on a team with team forms off."
  def check_on(%Team{forms_enabled: true}), do: :ok

  def check_on(%Team{name: name}),
    do: {:error, "#{name} has no team forms. SAR Duty turns them on for a team."}

  @doc "`{:ok, form}`, the team's own form `id`, or an error for the agent."
  def form(%Team{} = team, id) do
    with :ok <- check_on(team) do
      case Form.get(team, id) do
        nil -> {:error, "The team has no form #{id}. Use an id from list_forms."}
        form -> {:ok, form}
      end
    end
  end

  defp pages(form) do
    case Form.page_bytes(form) do
      nil -> {:ok, []}
      bytes -> Service.PDFGeometry.read(bytes)
    end
  end

  @doc "The output, from the form and its pages."
  def build(%Form{} = form, pages) do
    %{
      "name" => form.name,
      "state" => Atom.to_string(form.state),
      "version" => form.version,
      "text" => form.text,
      "language" => @language,
      "pages" => Enum.map(pages, &page/1)
    }
  end

  defp page(page) do
    %{
      "page" => page.number,
      "width" => page.width,
      "height" => page.height,
      "lines" => Enum.map(page.lines, &Map.take(&1, [:text, :x0, :x1, :top, :baseline, :size])),
      "blanks" => Enum.map(page.blanks, &Map.take(&1, [:x0, :x1, :baseline])),
      "rules" => Enum.map(page.rules, &Map.take(&1, [:x0, :x1, :y])),
      "boxes" => Enum.map(page.boxes, &Map.take(&1, [:x0, :x1, :top, :bottom]))
    }
    |> Map.new(fn
      {key, list} when is_list(list) -> {key, Enum.map(list, &string_keys/1)}
      other -> other
    end)
  end

  defp string_keys(map), do: Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
end
