defmodule App.Operation.PrintForm do
  @moduledoc """
  Prints a form for an activity (#950): reads the form's values for it
  (App.Operation.ReadDocument), adds what a person answered, and prints it on the
  form's own page (App.Operation.PrintDocument). Saving the PDF is the caller's, with
  `App.Model.SavedPDF.add_for_form!/5`.

  A form prints only for an activity its `where` shows it on. Its answers are checked
  as the form page checks them, by `App.Document.answers/2`.
  """

  alias App.Document
  alias App.Operation.PrintDocument
  alias App.Operation.ReadDocument
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Runner

  @doc """
  `{:ok, %{attachment, keep}}` or `{:error, reason}`: the PDF of form `text` on its page
  `page` for `activity_id`, with `answers` as typed by name, and the values it keeps.
  `sample: true` marks it SAMPLE, for made-up data.
  """
  def call(text, page, %Context{} = context, activity_id, answers \\ %{}, opts \\ []) do
    with {:ok, %{doc: doc, values: values}} <-
           ReadDocument.call(text, context, %{activity: activity_id}),
         :ok <- form?(doc),
         :ok <- shown?(doc, context, activity_id),
         {:ok, answered} <- answers(doc, answers) do
      output = Document.evaluate(doc, Map.merge(values, answered), context.timezone)
      print(output, doc.name, page, Keyword.get(opts, :sample, false))
    end
  end

  defp print(output, name, page, sample) do
    with {:ok, pdf} <- PrintDocument.call(output, page: page, sample: sample),
         do: {:ok, %{attachment: attachment(pdf, output.title || name), keep: output.keep}}
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
