defmodule App.Model.AIDraft do
  @moduledoc """
  A person's unsaved changes to one report or form, with AI writing's conversation
  (#1089): kept after every ask and every hand edit on Change report or Change form, so
  a reload, a closed tab, or a deploy loses nothing. One per person per report or form,
  and one per person per team for a new report. Only its author ever sees it.
  App.Operation.SaveDraft keeps, opens, and discards them; they go after
  30 days unchanged.

  `fields` is what the page holds: a report's `name`, `about`, `query`, and `values`, or
  a form's `text` and `page`, its PDF's SHA-256. `asks` is the conversation, newest
  first, as the page keeps it, with each PDF as its SHA-256. `pages` lists the PDFs
  kept in the file store under `files_token`: every one the draft has named but the
  form's saved page. A discarded draft with PDFs waits, `discarded_at` set and never
  found again, until App.Worker.DeleteDraftFilesWorker deletes them and the row.
  """
  use App, :model

  alias App.Accounts.User
  alias App.Model.AIDraft
  alias App.Model.Form
  alias App.Model.Organization
  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Repo

  @days 30

  schema "ai_drafts" do
    belongs_to :user, User
    # The report's team, or the form's team or organization.
    belongs_to :team, Team
    belongs_to :organization, Organization
    field :kind, Ecto.Enum, values: [:report, :form]
    # Nil for a new report.
    belongs_to :report, SavedReport
    belongs_to :form, Form
    field :fields, :map, redact: true
    field :asks, {:array, :map}, redact: true
    field :files_token, :string, redact: true
    field :pages, {:array, :string}, default: []
    field :discarded_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc "How many days a draft is kept after its last change."
  def days, do: @days

  @doc """
  The user's draft of `subject`, or nil: a `%Form{}`, or `{team, report}` for a report,
  `report` nil for a new one.
  """
  def get(%User{id: user_id}, subject),
    do: kept() |> where([d], d.user_id == ^user_id) |> for_subject(subject) |> Repo.one()

  @doc "Every draft of a form, each person's, discarded or not, for deleting the form."
  def all_for_form(%Form{id: id}), do: AIDraft |> where([d], d.form_id == ^id) |> Repo.all()

  @doc "Drafts unchanged for #{@days} days at `now`."
  def expired(now) do
    cutoff = DateTime.add(now, -@days, :day)
    kept() |> where([d], d.updated_at < ^cutoff) |> Repo.all()
  end

  @doc "The discarded draft `id` whose PDFs wait to be deleted, or nil."
  def get_discarded(id),
    do: AIDraft |> where([d], d.id == ^id and not is_nil(d.discarded_at)) |> Repo.one()

  defp kept, do: where(AIDraft, [d], is_nil(d.discarded_at))

  @doc "A new draft of `subject` for the user: its owner and what it's of, no content."
  def new(%User{id: user_id}, %Form{} = form),
    do: %AIDraft{
      user_id: user_id,
      kind: :form,
      form_id: form.id,
      team_id: form.team_id,
      organization_id: form.organization_id
    }

  def new(%User{id: user_id}, {%Team{id: team_id}, report}),
    do: %AIDraft{
      user_id: user_id,
      kind: :report,
      team_id: team_id,
      report_id: report && report.id
    }

  defp for_subject(query, %Form{id: id}), do: where(query, [d], d.form_id == ^id)

  defp for_subject(query, {%Team{}, %SavedReport{id: id}}),
    do: where(query, [d], d.report_id == ^id)

  defp for_subject(query, {%Team{id: team_id}, nil}),
    do: where(query, [d], d.kind == :report and d.team_id == ^team_id and is_nil(d.report_id))
end
