defmodule App.Operation.CreateFormPDF do
  @moduledoc """
  A team admin's PDF of an organization's form for an activity (#950): Download draft PDF on
  the activity's form page. It keeps the answers sent with it
  (App.Operation.SaveFormAnswers), prints the form with the activity's answers
  (App.Operation.PrintForm), marked DRAFT. A draft is never saved: publishing a form,
  saved with an ID, comes later. Nothing goes to D4H.

  The caller finds the form shown for the team (`App.Model.Form.get_shown/2`) and the
  activity through the team.
  """

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Form
  alias App.Model.FormAnswer
  alias App.Model.Team
  alias App.Operation.PrintForm
  alias App.Operation.SaveFormAnswers

  @doc """
  `{:ok, attachment}`, the draft PDF, or `{:error, reason}` with nothing printed.
  `typed` is the answers as the page sent them, `%{name => text}`.
  """
  def call(%Team{} = team, %Form{} = form, %Activity{} = activity, %User{} = user, typed, now) do
    with :ok <- check(team, form, activity),
         {:ok, doc, context} <- PrintForm.read(team, form.text, now),
         {:ok, _answers} <- save(activity, doc, typed, user, now),
         do: print(form, activity, doc, context)
  end

  # With the answers just kept, and the team's last for a question that remembers.
  defp print(form, activity, doc, context) do
    answers = FormAnswer.starting(activity, doc.asks)

    with {:ok, %{attachment: attachment}} <-
           PrintForm.call(form.text, Form.page_bytes(form), context, activity.id, answers,
             mark: :draft
           ),
         do: {:ok, attachment}
  end

  defp check(team, form, activity) do
    cond do
      activity.team_id != team.id -> {:error, "This activity is not on your team."}
      activity.deleted_at -> {:error, "This activity is deleted. Nothing can be made from it."}
      form.state == :off or form.organization_id != team.organization_id -> {:error, off()}
      true -> :ok
    end
  end

  defp off, do: "This form is turned off. Ask your organization to turn it on."

  defp save(activity, doc, typed, user, now) do
    case SaveFormAnswers.call(activity, doc, typed, user, now) do
      {:ok, answers} -> {:ok, answers}
      {:error, errors} -> {:error, PrintForm.errors_text(doc, errors)}
    end
  end
end
