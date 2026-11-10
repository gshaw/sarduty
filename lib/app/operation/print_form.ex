defmodule App.Operation.PrintForm do
  @moduledoc """
  Prints a form for an activity (#950): reads the form's values for it
  (App.Operation.ReadDocument), adds what a person answered, and prints it on the
  form's own page (App.Operation.PrintDocument). Nothing is saved.

  A form prints only for an activity its `where` shows it on. Its answers are checked
  as the form page checks them, by `App.Document.answers/2`.
  """

  alias App.Document
  alias App.Model.Team
  alias App.Operation.PrintDocument
  alias App.Operation.ReadDocument
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Runner

  @doc """
  `{:ok, %{attachment, keep}}` or `{:error, reason}`: the PDF of form `text` on its page
  `page` for `activity_id`, with `answers` as typed by name, and the values it keeps.
  `mark: :sample` marks it SAMPLE, for made-up data, and `mark: :draft` DRAFT
  (App.Operation.PrintDocument). `verify` is the verify link it's published under; without
  one it prints a draft's grey box where the verify code goes. Published, it refuses
  while a value the form `needs` is blank (#995); a draft prints without.
  """
  def call(text, page, %Context{} = context, activity_id, answers \\ %{}, opts \\ []) do
    verify = Keyword.get(opts, :verify, :draft)

    with {:ok, %{doc: doc} = read} <- read_shown(text, context, activity_id),
         {:ok, answered} <- answers(doc, answers),
         values = Map.merge(read.values, answered),
         :ok <- needs(verify, doc, values, read.read, context.timezone) do
      output = Document.evaluate(doc, sign(values, verify), context.timezone)
      print(output, doc.name, page, opts)
    end
  end

  # The form's values for the activity, once it's sure it's a form that shows there.
  defp read_shown(text, context, activity_id) do
    with {:ok, %{doc: doc} = read} <- ReadDocument.call(text, context, %{activity: activity_id}),
         :ok <- form?(doc),
         :ok <- shown?(doc, context, activity_id),
         do: {:ok, read}
  end

  defp needs(:draft, _doc, _values, _read, _timezone), do: :ok

  defp needs(_link, doc, values, read, timezone) do
    case ReadDocument.needed(doc, Document.values(doc, values, timezone), read) do
      [] -> :ok
      needed -> {:error, ReadDocument.needed_error("This form", needed)}
    end
  end

  defp print(output, name, page, opts) do
    print_opts = [page: page, mark: opts[:mark], verify: Keyword.get(opts, :verify, :draft)]

    with {:ok, pdf} <- PrintDocument.call(output, print_opts),
         do:
           {:ok,
            %{
              attachment: attachment(pdf, output.title || name),
              keep: output.keep,
              shows: output.shows
            }}
  end

  # Only a published PDF carries the team's signature (#970). A draft leaves it blank,
  # and its verify link with it.
  defp sign(values, :draft),
    do: Map.merge(values, %{"team.signature" => nil, "pdf.verify_link" => nil})

  defp sign(values, link), do: Map.put(values, "pdf.verify_link", link)

  @doc """
  `{:ok, doc, context}`, form `text` checked against `team`'s catalog as of `now`, or
  `{:error, message}`: what a draft and publishing read before they print.
  """
  def read(%Team{} = team, text, now) do
    context = Context.new(team, now)

    with {:ok, doc} <- Document.parse(text),
         {:ok, doc} <- Document.check(doc, context) do
      {:ok, doc, context}
    else
      {:error, %Error{} = error} -> {:error, Error.text(error)}
    end
  end

  defp form?(%Document{kind: :form}), do: :ok
  defp form?(_doc), do: {:error, "Start a form with form and its name."}

  @doc """
  `:ok` when checked form `doc` shows on `activity_id`, by its `where`, or `{:error,
  reason}`. The activity's page lists only the forms it shows on.
  """
  def shown?(%Document{} = doc, %Context{} = context, activity_id) do
    given = %{"activity" => to_string(activity_id)}

    with {:ok, plan} <- doc |> Document.shown_on() |> Compiler.compile(context, given),
         {:ok, result} <- Runner.run(plan, context.timezone, context.repo) do
      if result.rows == [], do: {:error, "This form is not for this activity."}, else: :ok
    end
  end

  defp answers(doc, typed) do
    case Document.answers(doc, typed) do
      {:ok, answered} -> {:ok, answered}
      {:error, errors} -> {:error, errors_text(doc, errors)}
    end
  end

  @doc """
  What's wrong with the answers, `%{name => message}`, each after its ask's label. An
  answer on each row says each of its rows' messages once.
  """
  def errors_text(%Document{} = doc, errors) do
    doc.asks
    |> Enum.filter(&Map.has_key?(errors, &1.name))
    |> Enum.map_join(" ", &"#{&1.label}: #{message(errors[&1.name])}")
  end

  defp message(rows) when is_map(rows), do: rows |> Map.values() |> Enum.uniq() |> Enum.join(" ")
  defp message(message), do: message

  defp attachment(pdf, title) do
    %{
      content: pdf,
      title: title,
      filename: Service.StringHelpers.to_filename("#{title}.pdf"),
      content_type: "application/pdf"
    }
  end
end
