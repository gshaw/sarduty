defmodule App.Operation.ReadDocument do
  @moduledoc """
  Reads what a document prints (#918, #950): checks its text against the team's
  catalog, runs each of its reports with the values it starts from, and adds today and
  the team's pictures. `App.Document.evaluate/3` then works out each place.

  A tax credit letter starts from a member and a year, and a form from an activity. The
  reports read the context's database, so a form tried on Coast Range SAR reads
  App.SampleRepo and nothing else.
  """

  alias App.Document
  alias App.Document.Evaluator
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.LoadImage
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Runner
  alias App.ViewData.ReportRecords

  @doc """
  `{:ok, %{doc, values, read}}`, the checked document and the values it reads, or
  `{:error, reason}`. `starts` holds what it starts from by name, such as `%{activity:
  7}`. `read` lists each report's columns in order, for a form's page to show what SAR
  Duty filled in: `%{name, label, column, value, from, custom?}`, where `from` is the
  report's subject, such as `activities` or `team`, and `custom?` says the column is one
  of the team's D4H custom fields. A record's value is its name.
  """
  def call(text, %Context{} = context, starts) when is_binary(text) and is_map(starts) do
    with {:ok, doc} <- Document.parse(text),
         {:ok, doc} <- Document.check(doc, context),
         {:ok, values, read} <- values(doc, context, starts) do
      {:ok, %{doc: doc, values: values, read: read}}
    else
      {:error, %Error{} = error} -> {:error, Error.text(error)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp values(doc, context, starts) do
    context = %{context | team: context.repo.preload(context.team, :organization)}
    given = Map.new(starts, fn {name, value} -> {to_string(name), to_string(value)} end)

    doc
    |> Document.queries()
    |> Enum.reduce_while({:ok, start(context, starts), []}, &add_report(&1, &2, context, given))
  end

  defp add_report({name, query}, {:ok, values, read}, context, given) do
    case put_report(values, name, query, context, given) do
      {:ok, values, entries} -> {:cont, {:ok, values, read ++ entries}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  # What it starts from as `:name`, the team's pictures, and today.
  defp start(context, starts) do
    context.team
    |> pictures()
    |> Map.merge(Map.new(starts, fn {name, value} -> {":#{name}", value} end))
    |> Map.put("today", context.today)
  end

  # The report's first row, added to `values`, and its columns as `read` lists them.
  defp put_report(values, name, query, context, given) do
    with {:ok, plan} <- Compiler.compile(query, context, given),
         {:ok, result} <- Runner.run(plan, context.timezone, context.repo) do
      records = ReportRecords.names(result, context.team, context.repo)
      values = Document.put_row(values, name, query, result, records)
      {:ok, values, read(values, name, query, result)}
    end
  end

  defp read(values, name, query, result) do
    query.select
    |> Enum.zip(result.columns)
    |> Enum.map(fn {ast, column} ->
      key = "#{name}.#{Evaluator.name(ast)}"

      %{
        name: key,
        label: column.label,
        column: column,
        value: Map.get(values, key),
        from: query.from,
        custom?: custom?(ast)
      }
    end)
  end

  # A D4H custom field is named in backticks, from the subject or a parent.
  defp custom?({:field, path, _args, _line}), do: path |> List.last() |> String.starts_with?("`")
  defp custom?(_ast), do: false

  # The logos and signature the team has when the PDF is printed; the saved PDF keeps
  # them (#918). A team without a logo gets none, not SAR Duty's.
  defp pictures(team) do
    %{
      "organization.logo" => organization_logo(team.organization),
      "team.logo" => if(Team.logo_file(team.subdomain), do: LoadImage.logo(team, :square)),
      "team.signature" => team.signature
    }
  end

  defp organization_logo(%Organization{logo: logo} = organization) when is_binary(logo),
    do: LoadImage.organization_logo(organization, :square)

  defp organization_logo(_organization), do: nil
end
