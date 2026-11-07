defmodule App.Model.FormAnswer do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.FormAnswer
  alias App.Model.Team
  alias App.Repo

  # A team admin's answer to a form's `ask` on an activity (#950), as they typed it. It's
  # the activity's, by the ask's name, so every form that asks the same thing starts from
  # it. Never sent to D4H. App.Operation.SaveFormAnswers writes them. docs/documents.md.
  schema "form_answers" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    field :name, :string
    # "" for one answer. An `ask each` keeps one for each row, by the row's member or
    # item, such as "member:12".
    field :row, :string, default: ""
    field :value, :string, redact: true
    # Who answered last, and when: updated_at.
    belongs_to :user, User
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  The activity's answers, `%{name => text}`, and for an answer on each row `%{name =>
  %{row => text}}`.
  """
  def for_activity(%Activity{id: id}) do
    FormAnswer
    |> where([a], a.activity_id == ^id)
    # Rows first, so one answer wins a name an older form asked for each row.
    |> order_by([a], desc: a.row)
    |> select([a], {a.name, a.row, a.value})
    |> Repo.all()
    |> Enum.reduce(%{}, &put_answer/2)
  end

  defp put_answer({name, "", text}, answers), do: Map.put(answers, name, text)

  defp put_answer({name, row, text}, answers),
    do: Map.update(answers, name, %{row => text}, &Map.put(&1, row, text))

  @doc "The team's last answer to each of `names` on any activity, `%{name => text}`."
  def last_answers(%Team{id: team_id}, names) do
    FormAnswer
    |> where([a], a.team_id == ^team_id and a.name in ^names and a.row == "")
    # Oldest first, so the newest of each name is the one the map keeps.
    |> order_by([a], asc: a.updated_at, asc: a.id)
    |> select([a], {a.name, a.value})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  What a form's asks start from on an activity, `%{name => text}`: the activity's answer,
  or for an ask that says `remember`, the team's last answer. An ask with neither is left
  out, so its default holds.
  """
  def starting(%Activity{} = activity, asks) do
    remembered = for %{remember: true, name: name} <- asks, do: name

    last =
      if remembered == [], do: %{}, else: last_answers(%Team{id: activity.team_id}, remembered)

    start(for_activity(activity), last, asks)
  end

  @doc """
  Pure: what each ask starts from, given the activity's answers and the team's last. An
  answer on each row starts from the activity's, `%{row => text}`.
  """
  def start(saved, last, asks) do
    for ask <- asks,
        answer = starting(ask, saved, last),
        answer not in [nil, false, "", %{}],
        into: %{},
        do: {ask.name, answer}
  end

  defp starting(%{each: report} = ask, saved, _last) when is_binary(report) do
    case Map.get(saved, ask.name) do
      rows when is_map(rows) -> rows
      _one -> nil
    end
  end

  defp starting(ask, saved, last),
    do: text(Map.get(saved, ask.name)) || (ask.remember && text(Map.get(last, ask.name)))

  defp text(text) when is_binary(text), do: text
  defp text(_rows_or_nil), do: nil
end
