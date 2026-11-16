defmodule App.Operation.TryForm do
  @moduledoc """
  Prints a form before it's turned on, marked SAMPLE, with every answer its default, and
  saves nothing. An organization's form prints on Coast Range SAR (#950), so its
  organization admins see it filled from made-up data in App.SampleRepo, never a team's
  people. A team's own form prints on one of the team's own activities (#1083), for its
  team admins, who already see them.
  """

  import Ecto.Query

  alias App.Document
  alias App.Model.Activity
  alias App.Model.Form
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.PrintForm
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Runner
  alias App.SampleRepo

  @limit 20

  @doc """
  The activities the form shows on that it's tried on, up to #{@limit}, newest first,
  that have started by `now`: Coast Range SAR's for an organization's form, the team's
  own for a team's. Empty when the form doesn't read there, or Coast Range SAR isn't
  seeded.
  """
  def activities(%Form{} = form, owner, now \\ DateTime.utc_now()) do
    with {%{} = context, repo} <- context(owner, now),
         {:ok, ids} <- ids_shown_on(form, context, repo) do
      Activity
      |> where([a], a.team_id == ^context.team.id and a.id in ^ids and a.started_at <= ^now)
      |> order_by([a], desc: a.started_at)
      |> limit(@limit)
      |> repo.all()
    else
      _other -> []
    end
  end

  defp ids_shown_on(form, context, repo) do
    with {:ok, doc} <- Document.parse(form.text),
         {:ok, doc} <- Document.check(doc, context),
         {:ok, plan} <- doc |> Document.activities_shown_on() |> Compiler.compile(context),
         {:ok, result} <- Runner.run(plan, context.timezone, repo),
         do: {:ok, Enum.map(result.rows, &hd/1)}
  end

  @doc """
  The activity a try starts on: the newest published one, since a team has filled in
  its fields by then, or the newest.
  """
  def first([]), do: nil
  def first(activities), do: Enum.find(activities, hd(activities), & &1.is_published)

  @doc """
  `{:ok, attachment}`, the form printed on the activity `activity_id` it's tried on, or
  `{:error, reason}`. `opts[:page]` prints it on that page PDF instead of the form's
  own, as Change form does with the agency's new PDF before it's saved (#1089).
  """
  def call(%Form{} = form, owner, activity_id, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    page = Keyword.get_lazy(opts, :page, fn -> Form.page_bytes(form) end)

    case context(owner, now) do
      {nil, _repo} ->
        {:error, "Coast Range SAR is not ready. Try again in a minute."}

      {context, _repo} ->
        with {:ok, %{attachment: attachment}} <-
               PrintForm.call(form.text, page, context, activity_id, %{}, mark: :sample),
             do: {:ok, attachment}
    end
  end

  defp context(%Organization{}, now) do
    case SampleRepo.team() do
      nil -> {nil, SampleRepo}
      team -> {Context.new(team, now, repo: SampleRepo), SampleRepo}
    end
  end

  defp context(%Team{} = team, now), do: {Context.new(team, now), App.Repo}
end
