defmodule App.Operation.SaveFormAnswers do
  @moduledoc """
  Keeps what a team admin answered on an activity's form (#950), in App.Model.FormAnswer:
  one row per name, shared by every form that asks it. Each answer is checked by its ask,
  as printing checks it (`App.Document.answers/2`). A blank one is deleted, so the form's
  default holds again. An `ask each` answer is kept for each row, by the row's member or
  item, unless it's the ask's plain default: a row's choice always sends one, and only
  a change from the default is worth keeping. Nothing goes to D4H.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Document
  alias App.Model.Activity
  alias App.Model.FormAnswer
  alias App.Repo

  @doc """
  Saves `typed`, `%{name => text}` as the form sent it, or `%{name => %{row => text}}`
  for an answer on each row, for the asks of checked form `doc`. Each answer that reads
  is saved, even when another doesn't. `{:ok, answers}` with the activity's answers
  after, or `{:error, %{name => message}}` for those that don't read.
  """
  def call(%Activity{} = activity, %Document{} = doc, typed, %User{} = user, now \\ nil) do
    now = now || DateTime.utc_now()
    plan = plan(doc, FormAnswer.for_activity(activity), typed)

    Repo.transaction(fn ->
      Enum.each(plan.put, fn {{name, row}, text} -> put!(activity, name, row, text, user, now) end)

      for {name, row} <- plan.delete do
        FormAnswer
        |> where([a], a.activity_id == ^activity.id and a.name == ^name and a.row == ^row)
        |> Repo.delete_all()
      end
    end)

    if plan.errors == %{},
      do: {:ok, FormAnswer.for_activity(activity)},
      else: {:error, plan.errors}
  end

  @doc """
  Pure: what saving `typed` changes, given the activity's `saved` answers: `%{put:
  %{{name, row} => text}, delete: [{name, row}], errors: %{name => message}}`, with row
  "" for one answer. Only `doc`'s asks count, and an answer that's the same as the saved
  one changes nothing.
  """
  def plan(%Document{} = doc, saved, typed) when is_map(saved) and is_map(typed) do
    initial = %{put: %{}, delete: [], errors: %{}}

    doc.asks
    |> Enum.filter(&Map.has_key?(typed, &1.name))
    |> Enum.reduce(initial, fn ask, plan ->
      plan_ask(plan, doc, ask, Map.get(typed, ask.name), Map.get(saved, ask.name))
    end)
  end

  defp plan_ask(plan, doc, %{each: nil} = ask, typed, saved) when not is_map(typed),
    do: step(plan, doc, ask.name, "", trim(typed), if(is_binary(saved), do: saved))

  defp plan_ask(plan, doc, %{each: each} = ask, typed, saved)
       when is_binary(each) and is_map(typed) do
    saved = if is_map(saved), do: saved, else: %{}

    Enum.reduce(typed, plan, fn {row, text}, plan ->
      text = text |> trim() |> unless_default(ask.default)
      step(plan, doc, ask.name, to_string(row), text, Map.get(saved, to_string(row)))
    end)
  end

  defp plan_ask(plan, _doc, _ask, _typed, _saved), do: plan

  defp unless_default(text, {:literal, value, _line}),
    do: if(text == to_string(value), do: "", else: text)

  defp unless_default(text, _default), do: text

  defp trim(text) when is_binary(text) or is_number(text),
    do: text |> to_string() |> String.trim()

  defp trim(_other), do: ""

  defp step(plan, _doc, _name, _row, "", nil), do: plan
  defp step(plan, _doc, name, row, "", _saved), do: %{plan | delete: [{name, row} | plan.delete]}
  defp step(plan, _doc, _name, _row, text, text), do: plan

  defp step(plan, doc, name, row, text, _saved) do
    typed = if row == "", do: %{name => text}, else: %{name => %{row => text}}

    case Document.answers(doc, typed) do
      {:ok, _answered} -> %{plan | put: Map.put(plan.put, {name, row}, text)}
      {:error, errors} -> %{plan | errors: Map.merge(plan.errors, errors, &merge_rows/3)}
    end
  end

  defp merge_rows(_name, a, b) when is_map(a) and is_map(b), do: Map.merge(a, b)
  defp merge_rows(_name, _a, b), do: b

  defp put!(activity, name, row, text, user, now) do
    Repo.insert!(
      %FormAnswer{
        team_id: activity.team_id,
        activity_id: activity.id,
        name: name,
        row: row,
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
