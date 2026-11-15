defmodule App.Document.Draft do
  @moduledoc """
  An agent's draft of a team's form (#1083). Each text `check_form` passes is kept for
  the team, the connection's user, and the form, and that user's Change page shows it
  as it arrives. Another admin never gets it. The team admin tries it and saves it; the
  agent never saves.

  It's kept in memory, not the database, for a day: a deploy forgets it, and the agent
  checks it again. A draft is the agent's text, its line on what changed, and its name;
  never anything read from the team.
  """

  use GenServer

  alias App.Model.Form
  alias App.Model.Team

  @table __MODULE__
  @keep_seconds 24 * 60 * 60

  defstruct [:text, :change, :agent, :at]

  @type t :: %__MODULE__{}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl GenServer
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  @doc "Keeps the agent's latest text, and sends it to the user's open Change page."
  def put(%Team{} = team, user_id, %Form{} = form, %__MODULE__{} = draft) do
    forget_old(draft.at)
    :ets.insert(@table, {key(team, user_id, form), draft})
    Phoenix.PubSub.broadcast(App.PubSub, topic(team, user_id, form), {:form_draft, draft})
  end

  @doc "The user's draft of the form, or nil: none, or one older than a day at `now`."
  def get(%Team{} = team, user_id, %Form{} = form, now \\ DateTime.utc_now()) do
    case :ets.lookup(@table, key(team, user_id, form)) do
      [{_key, draft}] -> if fresh?(draft, now), do: draft
      [] -> nil
    end
  end

  @doc "Forgets the user's draft of the form, once it's saved or thrown away."
  def delete(%Team{} = team, user_id, %Form{} = form) do
    :ets.delete(@table, key(team, user_id, form))
    Phoenix.PubSub.broadcast(App.PubSub, topic(team, user_id, form), {:form_draft, nil})
  end

  @doc "Follows the draft: `{:form_draft, draft}` arrives for each text the agent checks."
  def subscribe(%Team{} = team, user_id, %Form{} = form),
    do: Phoenix.PubSub.subscribe(App.PubSub, topic(team, user_id, form))

  defp key(team, user_id, form), do: {team.id, user_id, form.id}
  defp topic(team, user_id, form), do: "form_draft:#{team.id}:#{user_id}:#{form.id}"

  defp fresh?(draft, now), do: DateTime.diff(now, draft.at) < @keep_seconds

  defp forget_old(now) do
    for {key, draft} <- :ets.tab2list(@table),
        not fresh?(draft, now),
        do: :ets.delete(@table, key)

    :ok
  end
end
