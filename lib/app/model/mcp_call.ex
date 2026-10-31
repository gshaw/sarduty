defmodule App.Model.MCPCall do
  use App, :model

  alias App.Accounts.User
  alias App.Model.AgentConnection
  alias App.Model.MCPCall
  alias App.Model.Team
  alias App.Repo

  # Every MCP tool call (#28), to watch the trial from /admin/mcp. Generic per tool: the
  # tool's name, the arguments the agent sent, and how many rows it got back. Arguments
  # are dates, tags, and ids, never contact details. Kept 90 days, like login events.
  @retention_days 90

  schema "mcp_calls" do
    belongs_to :team, Team
    belongs_to :user, User
    belongs_to :agent_connection, AgentConnection
    field :tool, :string
    field :arguments, :map, default: %{}
    field :row_count, :integer
    field :error, :string
    field :duration_ms, :integer
    field :called_at, :utc_datetime_usec
  end

  @doc """
  Records a call. `attrs` takes `connection` (with `team_id` and `user_id`), `tool`,
  `arguments`, `row_count`, `error`, `duration_ms`, and `called_at`.
  """
  def record!(attrs) do
    attrs = Map.new(attrs)
    connection = attrs.connection

    Repo.insert!(%MCPCall{
      team_id: connection.team_id,
      user_id: connection.user_id,
      agent_connection_id: connection.id,
      tool: String.slice(attrs.tool, 0, 100),
      arguments: attrs[:arguments] || %{},
      row_count: attrs[:row_count],
      error: attrs[:error] && String.slice(attrs[:error], 0, 255),
      duration_ms: attrs[:duration_ms],
      called_at: attrs[:called_at] || DateTime.utc_now()
    })
  end

  @doc "The newest calls, newest first, with team, user, and agent connection."
  def get_recent(limit) do
    MCPCall
    |> order_by([c], desc: c.called_at, desc: c.id)
    |> limit(^limit)
    |> preload([:team, :user, :agent_connection])
    |> Repo.all()
  end

  @doc "Deletes calls older than #{@retention_days} days. Returns how many."
  def prune(now) do
    cutoff = DateTime.add(now, -@retention_days, :day)
    {count, _} = MCPCall |> where([c], c.called_at < ^cutoff) |> Repo.delete_all()
    count
  end
end
