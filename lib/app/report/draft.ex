defmodule App.Report.Draft do
  @moduledoc """
  An agent's live draft (#834). Each query `check_report` checks goes on a topic for the
  team, the connection's user, and the draft's id, and the report editor that user has
  open with that draft follows it. Another admin's editor never gets it. Nothing is
  stored: with no editor open, the agent's latest link still opens with its latest query.

  The update carries only what the agent sent and the agent's name from its connection.
  Whether the query runs, and what it finds, stays on the page: the agent's reply never
  waits on it.
  """

  alias App.Model.Team

  @id_bytes 12

  defstruct [:query, :name, :about, :change, :report_id, :agent, :at]

  @type t :: %__MODULE__{}

  @doc "A new draft id: random, url-safe."
  def new_id, do: @id_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc "Whether `id` looks like one `new_id/0` makes, so a link's id is safe in a topic."
  def id?(id) when is_binary(id), do: id =~ ~r/\A[A-Za-z0-9_-]{8,40}\z/
  def id?(_id), do: false

  @doc "Sends the agent's latest query to the editor following this draft, if one is open."
  def broadcast(%Team{} = team, user_id, id, %__MODULE__{} = draft) do
    Phoenix.PubSub.broadcast(App.PubSub, topic(team, user_id, id), {:report_draft, draft})
  end

  @doc "Follows the draft: `{:report_draft, draft}` arrives for each query the agent checks."
  def subscribe(%Team{} = team, user_id, id),
    do: Phoenix.PubSub.subscribe(App.PubSub, topic(team, user_id, id))

  def unsubscribe(%Team{} = team, user_id, id),
    do: Phoenix.PubSub.unsubscribe(App.PubSub, topic(team, user_id, id))

  defp topic(team, user_id, id), do: "report_draft:#{team.id}:#{user_id}:#{id}"
end
