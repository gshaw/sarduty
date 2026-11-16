defmodule App.AI.ReportJob do
  @moduledoc """
  An AI writing ask on the report editor: the system prompt, the tools, and the check of
  Claude's answer (App.AI.Job). Claude gets the rules, the report language
  (App.Report.Language), the team's names for things (`names/1`), the report as it
  stands, and the ask. Never a member, a row, or a count: rows come from the editor's
  preview, in SAR Duty, after Claude is done. App.AI.ReportJobTest seeds them and checks
  the request.
  """

  alias App.AI.Job
  alias App.AI.Tool.CheckReport
  alias App.AI.Tool.TryReport
  alias App.Model.Activity
  alias App.Model.Group
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Report
  alias App.Report.Catalog
  alias App.Report.CustomFields
  alias App.Report.Error
  alias App.Report.Language

  @rules """
  You write reports in SAR Duty, a web app for search and rescue teams. A report is a
  query in SAR Duty's report language, below. A team admin describes what they want, and
  you rewrite the report's query to do it.

  - Start from the query as it stands and change only what the ask needs.
  - Use only the subjects and fields in the language, and the team's names for groups,
    qualifications, tags, hours tags, and custom fields given after it. Write a custom
    field by its title in backticks.
  - Check each query with check_report before you answer. Use try_report to see whether
    it gives sensible rows on Coast Range SAR, a made-up team. Its names for things
    differ from this team's: answer with this team's.
  - You never see the team's members or records. The admin runs the report in SAR Duty.
  - Answer with the whole query, a name, and a note. The name is for a report that has
    none yet, at most 80 characters; give "" when it has one. The note is one short
    sentence for the admin in plain words: what you changed, or why you could not. No
    tool names, no field names in backticks.
  - When nothing in the language or the team's fields answers the ask, give "" as the
    query and say in the note what would work instead.
  """

  @schema %{
    "type" => "object",
    "properties" => %{
      "query" => %{"type" => "string"},
      "name" => %{"type" => "string"},
      "note" => %{"type" => "string"}
    },
    "required" => ["query", "name", "note"],
    "additionalProperties" => false
  }

  @doc """
  The job for `report`, a map of the editor's `query`, `name`, and `about`, and `ask`.
  Its result is `%{query:, name:, note:}`, with `name` nil unless the report had none.
  """
  def build(%Team{} = team, report, ask, now) do
    %Job{
      kind: :report,
      system: [@rules <> "\n" <> Language.markdown(), catalog(team)],
      tools: [CheckReport, TryReport],
      prompt: prompt(report, ask),
      schema: @schema,
      finish: &finish(&1, team, report, now),
      context: %{team: team, now: now},
      ask: ask
    }
  end

  defp prompt(report, ask) do
    """
    The report as it stands:
    Name: #{blank_or(report[:name], "(none yet)")}
    Description: #{blank_or(report[:about], "(none)")}
    Query:
    ```
    #{String.trim(report[:query] || "")}
    ```

    The admin asks: #{ask}
    """
  end

  defp blank_or(value, default) do
    case String.trim(value || "") do
      "" -> default
      text -> text
    end
  end

  @doc "Checks Claude's answer as the editor would, against the team's fields."
  def finish(output, %Team{} = team, report, now) do
    query = String.trim(output["query"] || "")
    note = String.trim(output["note"] || "")

    if query == "" or query == String.trim(report[:query] || "") do
      {:unchanged, note}
    else
      case Report.check(query, team, %{}, now) do
        {:ok, _plan} -> {:ok, %{query: query, name: name(output, report), note: note}}
        {:error, error} -> {:retry, Error.text(error)}
      end
    end
  end

  defp name(output, report) do
    with "" <- String.trim(report[:name] || ""),
         name when name != "" <- String.trim(output["name"] || "") do
      String.slice(name, 0, 80)
    else
      _has_one -> nil
    end
  end

  @doc """
  The team's names for things, as text for the prompt: its groups, qualifications, tags,
  hours tags, and the custom fields a report reads. How the team is organized, never who
  is in it or what they did. In a fixed order, so the prompt caches.
  """
  def catalog(%Team{} = team) do
    names = names(team)

    """
    This team is #{team.name}. Its names for things, as JSON:
    #{Jason.encode!(%{"groups" => names.groups, "qualifications" => names.qualifications, "tags" => names.tags, "hours_tags" => names.hours_tags, "custom_fields" => names.custom_fields}, pretty: true)}
    """
  end

  @doc "The team's names for things, as maps. MCP's report_fields gives the same."
  def names(%Team{} = team) do
    hours_tags = Activity.hours_tags(team)

    %{
      groups: team.id |> Group.get_all() |> titles(),
      qualifications: team.id |> Qualification.get_all() |> titles(),
      tags: team |> Catalog.read_tag_titles(App.Repo) |> Enum.map(&elem(&1, 0)) |> Enum.sort(),
      hours_tags: %{
        "primary" => hours_tags.primary,
        "secondary" => hours_tags.secondary,
        "other" => hours_tags[:other]
      },
      custom_fields: custom_fields(team)
    }
  end

  defp titles(records), do: records |> Enum.map(& &1.title) |> Enum.sort()

  @doc """
  Exactly the fields a report can read (App.Report.CustomFields), as a query writes them:
  an activity's for every kind, and a member's only when the team copies it. MCP's
  report_fields gives the same.
  """
  def custom_fields(team) do
    for {on, defs} when is_binary(on) <- CustomFields.read(team, App.Repo), d <- defs do
      %{
        "title" => d.title,
        "write" => "`#{d.title}`",
        "on" => on,
        "type" => Atom.to_string(d.type),
        "choices" =>
          if(d.type in [:choice, :list], do: d.options |> Enum.map(&elem(&1, 1)) |> Enum.uniq())
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)
    end
  end
end
