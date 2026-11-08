defmodule App.Operation.TryForm do
  @moduledoc """
  Prints an organization's form on Coast Range SAR (#950), so its organization admins
  see it filled before turning it on: made-up data from App.SampleRepo, marked SAMPLE,
  never a team's people. Every answer takes its default. Nothing is saved.
  """

  import Ecto.Query

  alias App.Document
  alias App.Model.Activity
  alias App.Model.Form
  alias App.Operation.PrintForm
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Runner
  alias App.SampleRepo

  @limit 20

  @doc """
  Coast Range SAR's activities the form shows on, up to #{@limit}, newest first, that
  have started by `now`. Empty when the form doesn't read or Coast Range SAR isn't
  seeded.
  """
  def activities(%Form{} = form, now \\ DateTime.utc_now()) do
    with %{} = context <- context(now),
         {:ok, ids} <- ids_shown_on(form, context) do
      Activity
      |> where([a], a.team_id == ^context.team.id and a.id in ^ids and a.started_at <= ^now)
      |> order_by([a], desc: a.started_at)
      |> limit(@limit)
      |> SampleRepo.all()
    else
      _other -> []
    end
  end

  defp ids_shown_on(form, context) do
    with {:ok, doc} <- Document.parse(form.text),
         {:ok, doc} <- Document.check(doc, context),
         {:ok, plan} <- doc |> Document.activities_shown_on() |> Compiler.compile(context),
         {:ok, result} <- Runner.run(plan, context.timezone, SampleRepo),
         do: {:ok, Enum.map(result.rows, &hd/1)}
  end

  @doc """
  The activity a try starts on: the newest published one, since a team has filled in
  its fields by then, or the newest.
  """
  def first([]), do: nil
  def first(activities), do: Enum.find(activities, hd(activities), & &1.is_published)

  @doc "`{:ok, attachment}`, the form printed on Coast Range SAR's activity, or `{:error, reason}`."
  def call(%Form{} = form, activity_id, now \\ DateTime.utc_now()) do
    case context(now) do
      nil ->
        {:error, "Coast Range SAR is not ready. Try again in a minute."}

      context ->
        with {:ok, %{attachment: attachment}} <-
               PrintForm.call(form.text, Form.page_bytes(form), context, activity_id, %{},
                 mark: :sample
               ),
             do: {:ok, attachment}
    end
  end

  defp context(now) do
    case SampleRepo.team() do
      nil -> nil
      team -> Context.new(team, now, repo: SampleRepo)
    end
  end
end
