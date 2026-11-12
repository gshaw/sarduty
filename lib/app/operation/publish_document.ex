defmodule App.Operation.PublishDocument do
  @moduledoc """
  The one way an organization's form publishes (#970): Publish on an activity's form
  page opens a preview, and Publish there keeps it. A draft is never saved; the preview
  prints once, with a new ID and its verify code, and publishing
  keeps that PDF, every answer it printed with, the values `keep` names, and what
  `verify shows` printed (App.Model.PublishedPDF).

  1. Checks that the activity is the team's, the form is on for it, and the person is a
     team admin.
  2. Reads the form for the activity, as a draft does, with its saved answers.
  3. Prints the preview, before any write, as letters do: a print that fails changes
     nothing.
  4. On Publish, checks again and saves the preview, in one transaction. The activity's
     current one becomes Replaced, and its History says who published it
     (App.ViewData.ChangeHistory).

  A form that says `signed by` is signed by whoever publishes it (#993,
  App.Operation.SignForm): the task leader in their own name, or another team admin in
  theirs, for the task leader. The preview prints that signature, so it covers what they
  looked at, and the PDF keeps who signed and whom for. Signed for them, the task leader
  gets an email with the PDF (App.Worker.EmailSignedFormWorker). When the Task Leader's
  Name changed since the preview, Publish refuses.

  `current_id` is the id of the activity's current PDF of this form the person saw, nil
  for none: when another admin published meanwhile, nothing is saved.
  """

  alias App.Accounts.User
  alias App.Document
  alias App.Model.Activity
  alias App.Model.DemoTeam
  alias App.Model.Form
  alias App.Model.FormAnswer
  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.Team
  alias App.Operation.PrintForm
  alias App.Operation.ReadDocument
  alias App.Operation.SignForm
  alias App.Repo
  alias App.Report.Context
  alias App.Worker.EmailSignedFormWorker

  @doc """
  The PDF as it would publish, printed and not saved, with the ID it publishes under:
  `{:ok, preview}` or `{:error, message}`. Its page shows the preview and Publish saves
  it with `publish/7`, so what's kept is what was looked at.
  """
  def preview(%Team{} = team, %Form{} = form, %Activity{} = activity, %User{} = user, now) do
    with :ok <- check(team, form, activity, user, now),
         {:ok, doc, context} <- PrintForm.read(team, form.text, now),
         {:ok, signer} <- signer(doc, team, user, now),
         do: print_preview({team, form, activity}, doc, context, signer)
  end

  # Printed once with a new ID, with the activity's answers, signed by `signer`.
  defp print_preview({team, form, activity}, doc, context, signer) do
    answers = FormAnswer.starting(activity, doc.asks)
    code = PublishedPDF.generate_code()

    with {:ok, printed} <- print(team, form, activity, context, {answers, signer}, code),
         do: {:ok, %{code: code, answers: answers, printed: printed, form_version: form.version}}
  end

  @doc """
  Saves a preview from `preview/5` as published: `{:ok, pdf}` or `{:error, message}`
  with nothing saved. It checks again, since the form or the person may have changed
  since, and refuses a preview of an older version of the form.
  """
  def publish(team, form, activity, user, preview, current_id, now \\ DateTime.utc_now()) do
    with :ok <- same_version(preview, form),
         :ok <- check(team, form, activity, user, now),
         :ok <- same_leader(team, form, activity, preview, now) do
      save(
        %{code: preview.code, answers: preview.answers},
        {team, form, activity, user},
        preview.printed,
        current_id
      )
    end
  end

  defp same_version(%{form_version: version}, %Form{version: version}), do: :ok

  defp same_version(_preview, _form),
    do: {:error, "The form changed since this preview. Go back and publish again."}

  # Who signs a form is the member publishing it, so a SAR Duty admin who isn't on the
  # team can't (#993).
  defp signer(%Document{signed_by: nil}, _team, _user, _now), do: {:ok, nil}

  defp signer(_doc, team, user, now) do
    case Member.find_by_email(team, user.email, now) do
      nil ->
        {:error,
         "Only a member of this team can sign this form. Log in with the email your team has for you."}

      member ->
        {:ok, member}
    end
  end

  # The signature in the preview names the task leader as they were then (#993).
  defp same_leader(_team, _form, _activity, %{printed: %{signed: nil}}, _now), do: :ok

  defp same_leader(team, form, activity, %{printed: %{signed: signed}}, now) do
    with {:ok, %{doc: doc, values: values}} <-
           ReadDocument.call(form.text, Context.new(team, now), %{activity: activity.id}),
         {:ok, answers} <- Document.answers(doc, FormAnswer.starting(activity, doc.asks)) do
      values = Map.merge(values, answers)

      if same_name?(Document.signed_by(doc, values, team.timezone), signed.leader_name),
        do: :ok,
        else: {:error, "The task leader changed. Go back and publish again."}
    end
  end

  defp same_name?(nil, nil), do: true

  defp same_name?(a, b) when is_binary(a) and is_binary(b),
    do: Member.same_name(a) == Member.same_name(b)

  defp same_name?(_a, _b), do: false

  @doc "Previews and publishes at once, as a test or a mockup does: `{:ok, pdf}` or `{:error, message}`."
  def call(
        %Team{} = team,
        %Form{} = form,
        %Activity{} = activity,
        %User{} = user,
        current_id,
        now
      ) do
    with {:ok, preview} <- preview(team, form, activity, user, now),
         do: publish(team, form, activity, user, preview, current_id, now)
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

  # The PDF, and the task leader's email when someone signed for them, in one
  # transaction.
  defp save(attrs, printed, current_id) do
    saved =
      Repo.transaction(fn ->
        case PublishedPDF.publish(attrs, printed, current_id) do
          {:ok, pdf} ->
            tell_leader(pdf, printed[:signed])
            pdf

          {:error, :stale} ->
            Repo.rollback(:stale)
        end
      end)

    case saved do
      {:ok, pdf} -> {:ok, pdf}
      {:error, :stale} -> {:error, "Someone just published this. Reload to see it."}
    end
  end

  defp tell_leader(pdf, signed) do
    if SignForm.tells_leader?(signed), do: EmailSignedFormWorker.enqueue(pdf, signed.leader)
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

  defp print(team, form, activity, context, {answers, signer}, code) do
    opts = [
      verify: PublishedPDF.verify_link(code),
      mark: if(DemoTeam.demo?(team), do: :sample),
      signer: signer
    ]

    case PrintForm.call(form.text, Form.page_bytes(form), context, activity.id, answers, opts) do
      {:ok, printed} -> {:ok, printed}
      {:error, %{} = errors} -> {:error, errors |> Map.values() |> Enum.join(" ")}
      {:error, message} -> {:error, message}
    end
  end
end
