defmodule App.Operation.PublishDocument do
  @moduledoc """
  The one way an organization's form publishes (#970): Publish on an activity's form
  page. A draft is never saved; publishing prints once, with a new ID, its verify code,
  and the team's signature, and keeps the PDF, every answer it printed with, the values
  `keep` names, and what `verify shows` printed (App.Model.PublishedPDF).

  1. Checks that the activity is the team's, the form is on for it, and the person is a
     team admin.
  2. Reads the form for the activity, as a draft does, with its saved answers.
  3. Prints, before the write transaction, as letters do: a print that fails changes
     nothing.
  4. Saves, in one transaction. The activity's current one becomes Replaced, and its
     History says who published it (App.ViewData.ChangeHistory).

  `current_id` is the id of the activity's current PDF of this form the person saw, nil
  for none: when another admin published meanwhile, nothing is saved.
  """

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.DemoTeam
  alias App.Model.Form
  alias App.Model.FormAnswer
  alias App.Model.PublishedPDF
  alias App.Model.Team
  alias App.Operation.PrintForm

  @doc "`{:ok, pdf}` or `{:error, message}` with nothing saved."
  def call(
        %Team{} = team,
        %Form{} = form,
        %Activity{} = activity,
        %User{} = user,
        current_id,
        now
      ) do
    with :ok <- check(team, form, activity, user, now),
         {:ok, doc, context} <- PrintForm.read(team, form.text, now),
         answers = FormAnswer.starting(activity, doc.asks),
         code = PublishedPDF.generate_code(),
         {:ok, printed} <- print(team, form, activity, context, answers, code) do
      save(%{code: code, answers: answers}, {team, form, activity, user}, printed, current_id)
    end
  end

  defp save(attrs, {team, form, activity, user}, printed, current_id) do
    attrs
    |> Map.merge(%{
      team_id: team.id,
      name: form.name,
      subject: subject(activity),
      activity_id: activity.id,
      form_id: form.id,
      form_version: form.version,
      user_id: user.id
    })
    |> save(printed, current_id)
  end

  defp save(attrs, printed, current_id) do
    case PublishedPDF.publish(attrs, printed, current_id) do
      {:ok, pdf} -> {:ok, pdf}
      {:error, :stale} -> {:error, "Someone just published this. Reload to see it."}
    end
  end

  @doc "An activity's subject, which its forms' PDFs are for: `activity:812`."
  def subject(%Activity{id: id}), do: "activity:#{id}"

  @doc """
  `:ok` when `user` may publish `form` for `activity` on `team`, or `{:error, message}`.
  The form page asks it before it shows Publish.
  """
  def check(team, form, activity, user, now) do
    cond do
      activity.team_id != team.id -> {:error, "This activity is not on your team."}
      activity.deleted_at -> {:error, "This activity is deleted. Nothing can be made from it."}
      form.organization_id != team.organization_id -> {:error, off()}
      form.state == :testing -> {:error, "This form is testing. Download a draft PDF instead."}
      form.state != :on -> {:error, off()}
      not team_admin?(team, user, now) -> {:error, "Only a team admin can publish a form."}
      true -> :ok
    end
  end

  defp off, do: "This form is turned off. Ask your organization to turn it on."

  @doc "Whether `user` is a team admin of `team`: one who manages it in D4H, or a SAR Duty admin."
  def team_admin?(_team, %User{is_admin: true}, _now), do: true
  def team_admin?(team, %User{email: email}, now), do: Team.managed_by?(team, email, now)

  defp print(team, form, activity, context, answers, code) do
    opts = [verify: PublishedPDF.verify_link(code), mark: if(DemoTeam.demo?(team), do: :sample)]

    case PrintForm.call(form.text, Form.page_bytes(form), context, activity.id, answers, opts) do
      {:ok, printed} -> {:ok, printed}
      {:error, %{} = errors} -> {:error, errors |> Map.values() |> Enum.join(" ")}
      {:error, message} -> {:error, message}
    end
  end
end
