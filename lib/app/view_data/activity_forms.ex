defmodule App.ViewData.ActivityForms do
  @moduledoc """
  An organization's forms on an activity (#950), for its team admins: which forms show on
  its Forms tab (#1018), and for one form's page what SAR Duty filled in, what's missing, and
  what each question starts from. Read-only: App.Operation.SaveFormAnswers keeps answers
  and App.Operation.CreateFormPDF makes the PDF.
  """

  alias App.Document
  alias App.Document.Evaluator
  alias App.Model.Activity
  alias App.Model.Form
  alias App.Model.FormAnswer
  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.SignRequest
  alias App.Model.Team
  alias App.Operation.AskToSign
  alias App.Operation.PrintForm
  alias App.Operation.PublishDocument
  alias App.Operation.ReadDocument
  alias App.Operation.SignForm
  alias App.Report.Context

  @doc """
  The forms on for the team's organization that show on the activity, by each form's
  `where`. None on a deleted activity. A form that no longer reads on the team shows, so
  its page can say why.
  """
  def on(%Team{} = team, %Activity{} = activity, now) do
    forms = if activity.deleted_at, do: [], else: Form.shown_for(team)

    case forms do
      [] ->
        []

      forms ->
        context = Context.new(team, now)
        Enum.filter(forms, &shown?(&1, context, activity))
    end
  end

  defp shown?(form, context, activity) do
    with {:ok, doc} <- Document.parse(form.text),
         {:ok, doc} <- Document.check(doc, context) do
      PrintForm.shown?(doc, context, activity.id) == :ok
    else
      {:error, _error} -> true
    end
  end

  @doc """
  One form's page: `{:ok, %{doc, values, timezone, read, filled, missing, needed,
  answers, rows}}`, `{:error, :not_shown}` when the form isn't for the activity, or
  `{:error, reason}` when it doesn't read on the team. `filled` and `missing` are what
  the form reads, as ReadDocument's `read` lists it, with a value or blank; `missing`
  leaves out what publishing needs, which is `needed` (`needed/2`). `answers` is what each question
  starts from, `%{name => text}`: the activity's answer, the team's last for one that
  says `remember`, or its default when that's a plain value; an answer on each row is
  `%{row => text}`, the activity's alone. `rows` is `rows/4`'s, from `values`, what the
  form read.
  """
  def load(%Team{} = team, %Activity{} = activity, %Form{} = form, now) do
    context = Context.new(team, now)

    with {:ok, %{doc: doc, read: read, values: values}} <-
           ReadDocument.call(form.text, context, %{activity: activity.id}),
         :ok <- shown_on(doc, context, activity) do
      {:ok, page(doc, values, read, FormAnswer.starting(activity, doc.asks), context.timezone)}
    end
  end

  defp page(doc, values, read, starting, timezone) do
    {missing, filled} = Enum.split_with(read, &blank?(&1.value))
    needs = MapSet.new(doc.needs, &Evaluator.name/1)
    answers = answers(doc, starting)

    page = %{
      doc: doc,
      values: values,
      timezone: timezone,
      read: read,
      filled: filled,
      missing: Enum.reject(missing, &MapSet.member?(needs, &1.name)),
      answers: answers,
      rows: rows(doc, values, answers, timezone)
    }

    Map.put(page, :needed, needed(page, answers))
  end

  @doc """
  What the form needs to publish that's blank with the answers `typed` (#995), each as
  `read` lists a value (App.Operation.ReadDocument.needed/3). Its page names each with
  the page that fills it, and Publish refuses while there's one. `page` is `load/4`'s.
  """
  def needed(%{doc: doc, values: values, read: read, timezone: timezone}, typed) do
    worked = Document.values(doc, Map.merge(values, readable(doc, typed)), timezone)
    ReadDocument.needed(doc, worked, read)
  end

  @doc """
  The places whose text likely goes on an attached page with the answers `typed`
  (#993), as `App.Document.attached/1` guesses from its length: each `%{read, lines}`,
  the name of the value it prints, as `read` lists it, and how many lines it has. A place
  that prints anything else, such as an answer or a value worked out, has `read` nil.
  `page` is `load/4`'s.
  """
  def attached(%{doc: doc, values: values, timezone: timezone}, typed) do
    doc
    |> Document.evaluate(Map.merge(values, readable(doc, typed)), timezone)
    |> Document.attached()
    |> Enum.map(&%{read: reads(doc, &1.name), lines: &1.lines})
  end

  # The value a place prints, when its fill is one value read straight from a report.
  defp reads(doc, place) do
    case Enum.find(doc.fill, &(&1.place == place)) do
      %{value: {:field, _path, [], _line} = field} -> Evaluator.name(field)
      _other -> nil
    end
  end

  @doc """
  The task leader a form that says `signed by` names with the answers `typed` (#993):
  App.Operation.SignForm.leader/4's `%{name, members}`, and `field`, the value it reads
  as `read` lists it, or an answer, for the page that fixes it. Nil for a form nobody
  signs. `page` is `load/4`'s.
  """
  def leader(%{doc: %{signed_by: nil}}, _typed, _team, _now), do: nil

  def leader(%{doc: doc, values: values, read: read, timezone: timezone}, typed, team, now) do
    name = Document.signed_by(doc, Map.merge(values, readable(doc, typed)), timezone)

    field =
      case doc.signed_by do
        {:value, ask, _line} ->
          %{from: :answer, label: Enum.find_value(doc.asks, ask, &(&1.name == ask && &1.label))}

        expr ->
          Enum.find(read, &(&1.name == Evaluator.name(expr)))
      end

    name |> SignForm.leader(team, now) |> Map.put(:field, field)
  end

  defp shown_on(doc, context, activity) do
    case PrintForm.shown?(doc, context, activity.id) do
      :ok -> :ok
      {:error, _reason} -> {:error, :not_shown}
    end
  end

  @doc """
  Pure: each ask's starting text, with a plain default for one that has no answer. An
  answer on each row is `%{row => text}`, the activity's answers alone: a blank one
  takes its default, which `rows/4` works out for each row.
  """
  def answers(%Document{asks: asks}, starting) do
    Map.new(asks, fn
      %{each: nil} = ask -> {ask.name, Map.get(starting, ask.name) || default(ask.default)}
      ask -> {ask.name, Map.get(starting, ask.name, %{})}
    end)
  end

  @doc """
  Pure: each report a form asks on each row of, or works a value out for on each row of,
  such as each equipment use's total, and its rows as the form works them out from
  `values`, what it read, with the answers `typed` (#950). For each report:
  `%{report, kind, asks, total, rows}`, where `kind` is the row's `:member` or `:item`,
  `asks` its `ask each`, and `total` the label of its last `compute each`, or nil. Each
  row is `%{key, dom, id, name, answers, defaults, total}`: `dom` a part of an element
  id unique in the table, `answers` what was typed for it, `defaults` what each answer
  is when its box is blank, and `total` that compute as the PDF prints it. An answer
  that doesn't read is left out until it does.
  """
  def rows(%Document{} = doc, values, typed, timezone) do
    answered = readable(doc, typed)
    # Each row's answers left out, so each takes its default.
    one_each = Map.reject(answered, fn {key, _value} -> is_tuple(key) end)

    worked = %{
      worked: Document.values(doc, Map.merge(values, answered), timezone),
      defaults: Document.values(doc, Map.merge(values, one_each), timezone),
      typed: typed,
      timezone: timezone
    }

    for report <- doc.reports,
        asks = Enum.filter(doc.asks, &(&1.each == report.name)),
        asks != [] or computes_each?(doc, report),
        do: table(doc, report, asks, worked)
  end

  defp computes_each?(doc, report), do: Enum.any?(doc.computes, &(&1.each == report.name))

  defp table(doc, report, asks, worked) do
    {kind, column} = record_column(report)
    total = doc.computes |> Enum.filter(&(&1.each == report.name)) |> List.last()
    table = %{doc: doc, asks: asks, column: column, total: total, timezone: worked.timezone}

    rows =
      worked.worked
      |> Map.get(report.name, [])
      |> Enum.zip(Map.get(worked.defaults, report.name, []))
      |> Enum.map(&row(&1, table, worked.typed))
      |> dom_ids(report.name)

    %{
      report: report.name,
      kind: kind,
      asks: asks,
      total: total && String.capitalize(total.name),
      rows: rows
    }
  end

  defp row({row, default}, table, typed) do
    %{
      key: row.key,
      id: row_id(row.key),
      name: row.values[table.column],
      answers: Map.new(table.asks, &{&1.name, typed |> Map.get(&1.name, %{}) |> at(row.key)}),
      defaults: Map.new(table.asks, &{&1.name, text(default.values[&1.name])}),
      total: total(row, table)
    }
  end

  # Each row's key, as an element id takes it, or the report and the row's number when
  # two rows share one, as two uses of one item do.
  defp dom_ids(rows, report) do
    keys = Enum.map(rows, & &1.key)
    keyed? = nil not in keys and Enum.uniq(keys) == keys

    rows
    |> Enum.with_index(1)
    |> Enum.map(fn {row, n} ->
      Map.put(
        row,
        :dom,
        if(keyed?, do: String.replace(row.key, ":", "-"), else: "#{report}-#{n}")
      )
    end)
  end

  # The row's total, as its `fill each` prints it.
  defp total(_row, %{total: nil}), do: nil

  defp total(row, %{doc: doc, total: total, timezone: timezone}),
    do: Document.printed(doc, total.name, row.values[total.name], timezone)

  # What was typed that reads: an answer that doesn't is left out, so its default holds.
  defp readable(doc, typed) do
    case Document.answers(doc, typed) do
      {:ok, answered} ->
        answered

      {:error, errors} ->
        typed
        |> Map.new(fn {name, value} -> {name, drop_errors(value, errors[name])} end)
        |> then(&readable(doc, &1))
    end
  end

  defp drop_errors(_value, message) when is_binary(message), do: nil

  defp drop_errors(rows, errors) when is_map(rows) and is_map(errors),
    do: Map.drop(rows, Map.keys(errors))

  defp drop_errors(value, nil), do: value

  # The report's first member or item, which keeps each row's answers, and its name in a
  # row's values.
  defp record_column(report) do
    report.query.select
    |> Enum.zip(report.columns)
    |> Enum.find_value({nil, nil}, fn
      {ast, %{type: {:record, kind}}} when kind in [:member, :item] ->
        {kind, Evaluator.name(ast)}

      _other ->
        nil
    end)
  end

  defp row_id(nil), do: nil
  defp row_id(key), do: key |> String.split(":") |> List.last() |> String.to_integer()

  defp at(rows, key) when is_map(rows), do: Map.get(rows, key)
  defp at(_text, _key), do: nil

  defp text(nil), do: ""
  defp text(%Decimal{} = n), do: Decimal.to_string(n, :normal)
  defp text(value), do: to_string(value)

  @doc """
  The form's PDFs published for the activity (#970): `%{current, all}`, the current one
  or nil, and every one, newest first, for its History.
  """
  def published(%Team{} = team, %Activity{} = activity, %Form{} = form) do
    all = PublishedPDF.get_all_for(team.id, form.name, PublishDocument.subject(activity))
    %{current: Enum.find(all, &(PublishedPDF.status(&1) == :current)), all: all}
  end

  @doc """
  What reads differently on `pdf`'s verify page if the form were published today, with
  the activity's answers now (PublishedPDF.changes/2): `[]` when nothing does, or a line
  for each value, `"Total claimed: $1,240.00 → $1,310.00"`. `page` is `load/4`'s.
  """
  def changes(%{doc: doc, values: values, timezone: timezone}, starting, %PublishedPDF{} = pdf) do
    output = Document.evaluate(doc, Map.merge(values, readable(doc, starting)), timezone)
    PublishedPDF.changes(pdf, output)
  end

  @doc """
  The Forms tab's rows (#1018), one per form, in order: `%{form, state, pdf, waiting}`.
  `state` is `:testing` for a form that prints drafts only, `:waiting` while a request
  to sign it is open (#993), else `:published`, `:out_of_date`, or `:not_published`.
  `pdf` is the current published PDF, or nil, and `waiting` the member asked to sign.
  A request whose Task Leader's Name no longer names who it asks isn't waiting: the
  form's page ends it.
  """
  def list(%Team{} = team, %Activity{} = activity, forms, now) do
    Enum.map(forms, &row(team, activity, &1, now))
  end

  defp row(_team, _activity, %Form{state: :testing} = form, _now),
    do: %{form: form, state: :testing, pdf: nil, waiting: nil}

  defp row(team, activity, form, now) do
    pdf = published(team, activity, form).current
    request = SignRequest.open_for(activity, form)

    page = if pdf || request, do: loaded(team, activity, form, now)
    waiting = waiting(request, page, team, now)
    %{form: form, state: state(pdf, page, activity, waiting), pdf: pdf, waiting: waiting}
  end

  # The form's page, or nil when it doesn't read on the team.
  defp loaded(team, activity, form, now) do
    case load(team, activity, form, now) do
      {:ok, page} -> page
      {:error, _reason} -> nil
    end
  end

  defp waiting(nil, _page, _team, _now), do: nil
  defp waiting(_request, nil, _team, _now), do: nil

  defp waiting(request, page, team, now) do
    found = leader(page, page.answers, team, now)
    if found && not AskToSign.leader_changed?(request, found), do: request.member
  end

  defp state(_pdf, _page, _activity, %Member{}), do: :waiting
  defp state(nil, _page, _activity, nil), do: :not_published
  defp state(_pdf, nil, _activity, nil), do: :published

  defp state(pdf, page, activity, nil) do
    starting = FormAnswer.starting(activity, page.doc.asks)
    if changes(page, starting, pdf) == [], do: :published, else: :out_of_date
  end

  @doc "How many of `list/4`'s rows are out of date: the Forms tab's count."
  def out_of_date(rows), do: Enum.count(rows, &(&1.state == :out_of_date))

  @doc "The asks the page shows, one answer each."
  def questions(%Document{asks: asks}), do: Enum.filter(asks, &is_nil(&1.each))

  defp default({:literal, value, _line}), do: to_string(value)
  defp default(_value_or_nil), do: nil

  @doc "Blank, as a form prints it: nil, empty text, or an empty list."
  def blank?(value), do: value in [nil, "", []]
end
