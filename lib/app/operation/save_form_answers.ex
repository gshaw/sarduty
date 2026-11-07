defmodule App.Operation.SaveFormAnswers do
  @moduledoc """
  Keeps what a team admin answered on an activity's form (#950), in App.Model.FormAnswer:
  one row per name, shared by every form that asks it. Each answer is checked by its ask,
  as printing checks it (`App.Document.answers/2`). A blank one is deleted, so the form's
  default holds again. Nothing goes to D4H.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Document
  alias App.Model.Activity
  alias App.Model.FormAnswer
  alias App.Repo

  @doc """
  Saves `typed`, `%{name => text}` as the form sent it, for the asks of checked form
  `doc`. Each answer that reads is saved, even when another doesn't. `{:ok, answers}`
  with the activity's answers after, or `{:error, %{name => message}}` for those that
  don't read.
  """
  def call(%Activity{} = activity, %Document{} = doc, typed, %User{} = user, now \\ nil) do
    now = now || DateTime.utc_now()
    plan = plan(doc, FormAnswer.for_activity(activity), typed)

    Repo.transaction(fn ->
      Enum.each(plan.put, fn {name, text} -> put!(activity, name, text, user, now) end)

      FormAnswer
      |> where([a], a.activity_id == ^activity.id and a.row == "" and a.name in ^plan.delete)
      |> Repo.delete_all()
    end)

    if plan.errors == %{},
      do: {:ok, FormAnswer.for_activity(activity)},
      else: {:error, plan.errors}
  end

  @doc """
  Pure: what saving `typed` changes, given the activity's `saved` answers: `%{put: %{name
  => text}, delete: [name], errors: %{name => message}}`. Only `doc`'s asks count, and
  an answer that's the same as the saved one changes nothing.
  """
  def plan(%Document{} = doc, saved, typed) when is_map(saved) and is_map(typed) do
    initial = %{put: %{}, delete: [], errors: %{}}

    doc.asks
    |> Enum.filter(&Map.has_key?(typed, &1.name))
    |> Enum.reduce(initial, fn ask, plan ->
      text = typed |> Map.get(ask.name) |> to_string() |> String.trim()
      step(plan, doc, ask.name, text, Map.get(saved, ask.name))
    end)
  end

  defp step(plan, _doc, _name, "", nil), do: plan
  defp step(plan, _doc, name, "", _saved), do: %{plan | delete: [name | plan.delete]}
  defp step(plan, _doc, _name, text, text), do: plan

  defp step(plan, doc, name, text, _saved) do
    case Document.answers(doc, %{name => text}) do
      {:ok, _answered} -> %{plan | put: Map.put(plan.put, name, text)}
      {:error, errors} -> %{plan | errors: Map.merge(plan.errors, errors)}
    end
  end

  defp put!(activity, name, text, user, now) do
    Repo.insert!(
      %FormAnswer{
        team_id: activity.team_id,
        activity_id: activity.id,
        name: name,
        row: "",
        value: text,
        user_id: user.id,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: [set: [value: text, user_id: user.id, updated_at: now]],
      conflict_target: [:activity_id, :name, :row]
    )
  end
end
