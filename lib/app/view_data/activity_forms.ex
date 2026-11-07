defmodule App.ViewData.ActivityForms do
  @moduledoc """
  An organization's forms on an activity (#950), for its team admins: which forms show on
  it, above Actions, and for one form's page what SAR Duty filled in, what's missing, and
  what each question starts from. Read-only: App.Operation.SaveFormAnswers keeps answers
  and App.Operation.CreateFormPDF makes the PDF.
  """

  alias App.Document
  alias App.Model.Activity
  alias App.Model.Form
  alias App.Model.FormAnswer
  alias App.Model.Team
  alias App.Operation.PrintForm
  alias App.Operation.ReadDocument
  alias App.Report.Context

  @doc """
  The forms on for the team's organization that show on the activity, by each form's
  `where`. None on a deleted activity. A form that no longer reads on the team shows, so
  its page can say why.
  """
  def on(%Team{} = team, %Activity{} = activity, now) do
    forms = if activity.deleted_at, do: [], else: Form.enabled_for(team)

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
  One form's page: `{:ok, %{doc, filled, missing, answers}}`, `{:error, :not_shown}` when
  the form isn't for the activity, or `{:error, reason}` when it doesn't read on the team.
  `filled` and `missing` are what the form reads, as ReadDocument's `read` lists it,
  with a value or blank. `answers` is what each question starts from, `%{name => text}`:
  the activity's answer, the team's last for one that says `remember`, or its default
  when that's a plain value.
  """
  def load(%Team{} = team, %Activity{} = activity, %Form{} = form, now) do
    context = Context.new(team, now)

    with {:ok, %{doc: doc, read: read}} <-
           ReadDocument.call(form.text, context, %{activity: activity.id}),
         :ok <- shown_on(doc, context, activity) do
      {missing, filled} = Enum.split_with(read, &blank?(&1.value))

      {:ok,
       %{
         doc: doc,
         filled: filled,
         missing: missing,
         answers: answers(doc, FormAnswer.starting(activity, doc.asks))
       }}
    end
  end

  defp shown_on(doc, context, activity) do
    case PrintForm.shown?(doc, context, activity.id) do
      :ok -> :ok
      {:error, _reason} -> {:error, :not_shown}
    end
  end

  @doc "Pure: each ask's starting text, with a plain default for one that has no answer."
  def answers(%Document{asks: asks}, starting) do
    Map.new(asks, fn ask -> {ask.name, Map.get(starting, ask.name) || default(ask.default)} end)
  end

  defp default({:literal, value, _line}), do: to_string(value)
  defp default(_value_or_nil), do: nil

  @doc "Blank, as a form prints it: nil, empty text, or an empty list."
  def blank?(value), do: value in [nil, "", []]
end
