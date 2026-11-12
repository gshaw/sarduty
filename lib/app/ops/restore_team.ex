defmodule App.Ops.RestoreTeam do
  @moduledoc """
  Puts a deleted team back from the copy `App.Operation.DeleteTeam` kept for 7 days.
  The admins' email names the copy and the event holds the team's id.
  """

  use App.Ops.Task,
    name: "restore-team",
    usage: "fix restore-team COPY TEAM_ID",
    summary: "Puts a deleted team back from its 7-day copy.",
    write: true

  alias App.Operation.RestoreTeam

  @impl App.Ops.Task
  def run([path, team_id]) do
    with {id, ""} <- Integer.parse(team_id),
         {:ok, rows} <- RestoreTeam.call(path, id) do
      rows = rows |> Enum.sort() |> Enum.map(fn {table, count} -> [to_string(table), count] end)
      {:ok, %{columns: ["table", "rows put back"], rows: rows}}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
      _ -> usage_error()
    end
  end

  def run(_args), do: usage_error()

  defp usage_error, do: {:error, "Usage: " <> usage()}
end
