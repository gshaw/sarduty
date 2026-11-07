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
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.LoadImage
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Runner
  alias App.ViewData.ReportRecords

  @doc """
  `{:ok, %{doc, values}}`, the checked document and the values it reads, or `{:error,
  reason}`. `starts` holds what it starts from by name, such as `%{activity: 7}`.
  """
  def call(text, %Context{} = context, starts) when is_binary(text) and is_map(starts) do
    with {:ok, doc} <- Document.parse(text),
         {:ok, doc} <- Document.check(doc, context),
         {:ok, values} <- values(doc, context, starts) do
      {:ok, %{doc: doc, values: values}}
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
    |> Enum.reduce_while({:ok, start(context, starts)}, fn {name, query}, {:ok, values} ->
      case put_report(values, name, query, context, given) do
        {:ok, values} -> {:cont, {:ok, values}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # What it starts from as `:name`, the team's pictures, and today.
  defp start(context, starts) do
    context.team
    |> pictures()
    |> Map.merge(Map.new(starts, fn {name, value} -> {":#{name}", value} end))
    |> Map.put("today", context.today)
  end

  # The report's first row, added to `values`.
  defp put_report(values, name, query, context, given) do
    with {:ok, plan} <- Compiler.compile(query, context, given),
         {:ok, result} <- Runner.run(plan, context.timezone, context.repo) do
      records = ReportRecords.names(result, context.team, context.repo)
      {:ok, Document.put_row(values, name, query, result, records)}
    end
  end

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
