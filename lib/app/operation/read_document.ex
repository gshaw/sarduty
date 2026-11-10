defmodule App.Operation.ReadDocument do
  @moduledoc """
  Reads what a document prints (#918, #950): checks its text against the team's
  catalog, runs each of its reports with the values it starts from, and adds today and
  the team's pictures. `App.Document.evaluate/3` then works out each place.

  A tax credit letter starts from a member and a year, and a form from an activity. The
  reports read the context's database, so a form tried on Coast Range SAR reads
  App.SampleRepo and nothing else. A report with a row each, which a form's `compute
  each` or `ask each` reads, adds every row (`App.Document.put_rows/5`) and nothing to
  `read`.
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
    with {:ok, [read]} <- call_each(text, context, [starts]), do: {:ok, read}
  end

  @doc """
  `call/3` for many starts at once, such as each member's letter for a year (#995):
  `{:ok, [%{doc, values, read}]}` in the order of `starts`, or `{:error, reason}` for
  the first that doesn't read. The document is parsed and checked once, and the team's
  pictures and the reports every start shares, `team` and `organization`, read once.
  The rest run for each start.
  """
  def call_each(text, %Context{} = context, starts) when is_binary(text) and is_list(starts) do
    context = %{context | team: context.repo.preload(context.team, :organization)}

    with {:ok, doc} <- Document.parse(text),
         {:ok, doc} <- Document.check(doc, context),
         {:ok, shared} <- shared(doc, context) do
      each(doc, context, shared, starts)
    else
      {:error, %Error{} = error} -> {:error, Error.text(error)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp each(doc, context, shared, starts) do
    result =
      Enum.reduce_while(starts, {:ok, []}, fn one, {:ok, reads} ->
        case values(doc, context, shared, one) do
          {:ok, values, read} -> {:cont, {:ok, [%{doc: doc, values: values, read: read} | reads]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    with {:ok, reads} <- result, do: {:ok, Enum.reverse(reads)}
  end

  @picture_labels %{
    "team.signature" => "Signer's signature",
    "team.logo" => "Logo",
    "organization.logo" => "Organization logo"
  }

  @doc """
  `{:ok, %{doc, values, read, labels}}` with only the team's and the organization's
  values the document reads, and the team's pictures: what its `needs` asks about of the
  team (#970). `read` lists them as `call/3` does, and `labels` names each, pictures
  too, `"team.signer" => "Signer"`. Runs no other report, so it needs nothing to start
  from.
  """
  def settings(text, %Context{} = context) when is_binary(text) do
    context = %{context | team: context.repo.preload(context.team, :organization)}

    with {:ok, doc} <- Document.parse(text),
         {:ok, doc} <- Document.check(doc, context) do
      {:ok, shared} = shared(doc, context)
      {:ok, values, read} = values(%{doc | reports: []}, context, shared, %{})
      {:ok, %{doc: doc, values: values, read: read, labels: labels(read)}}
    else
      {:error, %Error{} = error} -> {:error, Error.text(error)}
    end
  end

  defp labels(read), do: Map.merge(@picture_labels, Map.new(read, &{&1.name, &1.label}))

  @doc """
  What `doc` needs to publish that's missing from `values` (#995), blank or false
  (App.Document.missing/2), each as `read` lists a value, `%{name, label, from, custom?,
  value}`: a team setting or picture (`from: "team"`), a report's value, such as an
  activity's field or whether it's published, or an answer (`from: :answer`), labelled
  as its ask is. Publishing refuses while there's one, with `needed_error/2`; a draft
  prints without them. Give `values` with the answers and computes, as
  `App.Document.values/3` works them out, for a form that needs one.
  """
  def needed(%Document{} = doc, values, read) do
    by_name = Map.new(read, &{&1.name, &1})

    for name <- Document.missing(doc, values) do
      entry = Map.get(by_name, name) || unread(doc, name)
      Map.put(entry, :value, Map.get(values, name))
    end
  end

  @doc """
  The state a need waits for when it's false, such as an activity's: `:published`,
  `:finished`, `:other` for another yes or no, or nil for a value that's blank.
  """
  def waits_for(%{value: false, from: "activities", name: name}) do
    case name |> String.split(".") |> List.last() do
      "published" -> :published
      "finished" -> :finished
      _other -> :other
    end
  end

  def waits_for(%{value: false}), do: :other
  def waits_for(_need), do: nil

  defp unread(doc, ":" <> ask) do
    label = Enum.find_value(doc.asks, ask, &(&1.name == ask && &1.label))
    %{name: ":#{ask}", label: label, from: :answer, custom?: false}
  end

  defp unread(_doc, name) do
    [from | _rest] = String.split(name, ".")
    %{name: name, label: @picture_labels[name] || name, from: from, custom?: false}
  end

  @doc """
  Publishing's refusal while `needed/3` names something, starting with `what`, such as
  "This letter": "This letter cannot be published without the signer's signature.",
  or for a state it waits for, "This form cannot be published until the activity is
  published." `verb` is what the person's button does, so a letter, which only Email
  publishes, says "emailed" (#995). The page's warning banner says the same, with the
  page that fills each.
  """
  def needed_error(what, needed, verb \\ "published") do
    {states, blanks} = Enum.split_with(needed, &waits_for/1)

    case {states, blanks} do
      {[], blanks} ->
        "#{what} cannot be #{verb} #{without(blanks)}."

      {states, []} ->
        "#{what} cannot be #{verb} until #{until(states)}."

      {states, blanks} ->
        "#{what} cannot be #{verb} until #{until(states)}. It needs #{needs_too(blanks)}."
    end
  end

  defp without([one]), do: "without the #{lower(one.label)}"

  defp without(blanks),
    do:
      "without #{length(blanks)} values: #{Service.Format.and_list(Enum.map(blanks, &lower(&1.label)))}"

  defp needs_too([one]), do: "the #{lower(one.label)} too"

  defp needs_too(blanks),
    do:
      "#{length(blanks)} values too: #{Service.Format.and_list(Enum.map(blanks, &lower(&1.label)))}"

  # The activity's states as one phrase, then any other yes or no by its label.
  defp until(states) do
    waits = Enum.map(states, &waits_for/1)

    activity =
      case {:finished in waits, :published in waits} do
        {true, true} -> ["the activity finishes and is published"]
        {true, false} -> ["the activity finishes"]
        {false, true} -> ["the activity is published"]
        {false, false} -> []
      end

    others = for need <- states, waits_for(need) == :other, do: "#{lower(need.label)} is yes"
    Service.Format.and_list(activity ++ others)
  end

  @doc "A label mid-sentence: its first letter lower case, unless it starts an acronym, as SAR."
  def lower(<<first::utf8, second::utf8, _rest::binary>> = label)
      when first in ?A..?Z and second in ?A..?Z,
      do: label

  def lower(<<first::utf8, rest::binary>>), do: String.downcase(<<first::utf8>>) <> rest
  def lower(label), do: label

  # The reports every start reads alike: the team's and its organization's one row.
  @shared ~w(team organization)

  # The team's pictures and today, and each shared report's values and `read`, by name.
  defp shared(doc, context) do
    base = context.team |> pictures() |> Map.put("today", context.today)

    doc.reports
    |> Enum.filter(&(&1.name in @shared))
    |> Enum.reduce_while({:ok, %{base: base, reports: %{}}}, fn report, {:ok, shared} ->
      case put_report(%{}, report, context, %{}) do
        {:ok, values, read} ->
          {:cont, {:ok, put_in(shared, [:reports, report.name], {values, read})}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # Each report in order, a shared one from `shared`, on what it starts from as `:name`.
  # A shared one `settings/2` leaves out of `doc` still adds its values.
  defp values(doc, context, shared, starts) do
    given = Map.new(starts, fn {name, value} -> {to_string(name), to_string(value)} end)
    start = Map.merge(shared.base, Map.new(starts, fn {name, value} -> {":#{name}", value} end))
    {start, read} = add_unlisted(start, doc, shared)

    Enum.reduce_while(
      doc.reports,
      {:ok, start, read},
      &add_report(&1, &2, context, given, shared)
    )
  end

  defp add_unlisted(values, doc, shared) do
    listed = MapSet.new(doc.reports, & &1.name)

    for {name, {report_values, entries}} <- shared.reports,
        not MapSet.member?(listed, name),
        reduce: {values, []} do
      {values, read} -> {Map.merge(values, report_values), read ++ entries}
    end
  end

  defp add_report(report, {:ok, values, read}, context, given, shared) do
    case Map.fetch(shared.reports, report.name) do
      {:ok, {report_values, entries}} ->
        {:cont, {:ok, Map.merge(values, report_values), read ++ entries}}

      :error ->
        case put_report(values, report, context, given) do
          {:ok, values, entries} -> {:cont, {:ok, values, read ++ entries}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end
  end

  # The report's first row, or every row, added to `values`, and its columns as `read`
  # lists them.
  defp put_report(values, %{name: name, query: query} = report, context, given) do
    with {:ok, plan} <- Compiler.compile(query, context, given),
         {:ok, result} <- Runner.run(plan, context.timezone, context.repo) do
      records = ReportRecords.names(result, context.team, context.repo)

      if Map.get(report, :rows, false) do
        {:ok, Document.put_rows(values, name, query, result, records), []}
      else
        values = Document.put_row(values, name, query, result, records)
        {:ok, values, read(values, name, query, result)}
      end
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
