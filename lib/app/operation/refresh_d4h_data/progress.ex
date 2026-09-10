defmodule App.Operation.RefreshD4HData.Progress do
  @moduledoc """
  Tracks and broadcasts progress during D4H data refresh operations.
  """

  alias App.Model.Team

  defstruct [
    :team_id,
    :stage,
    :processed_count,
    :total_count
  ]

  def new(team_id) do
    %__MODULE__{
      team_id: team_id,
      stage: "Starting",
      processed_count: 0,
      total_count: nil
    }
  end

  def update_stage(progress, stage) when is_binary(stage) do
    progress = %{progress | stage: stage, processed_count: 0, total_count: nil}
    broadcast_progress(progress)
    progress
  end

  def update_stage(progress, stage, total_count) when is_binary(stage) do
    progress = %{progress | stage: stage, total_count: total_count, processed_count: 0}
    broadcast_progress(progress)
    progress
  end

  def add_page(progress, page_count) do
    new_count = progress.processed_count + page_count
    progress = %{progress | processed_count: new_count}
    broadcast_progress(progress)
    progress
  end

  def finish_stage(progress) do
    progress = %{progress | processed_count: progress.total_count || progress.processed_count}
    broadcast_progress(progress)
    progress
  end

  def complete(progress) do
    progress = %{
      progress
      | stage: "Complete",
        processed_count: progress.total_count || progress.processed_count
    }

    broadcast_progress(progress)
    progress
  end

  def format_status(%__MODULE__{} = progress) do
    stage = progress.stage
    count = progress.processed_count

    cond do
      count == 0 && progress.total_count ->
        "#{stage}..."

      count == 0 && is_nil(progress.total_count) ->
        "#{stage}: Refreshing..."

      progress.total_count ->
        percentage = round(count / progress.total_count * 100)
        "#{stage}: #{count}/#{progress.total_count} (#{percentage}%)"

      true ->
        "#{stage}: #{count}"
    end
  end

  defp broadcast_progress(progress) do
    team = Team.get!(progress.team_id)
    status = format_status(progress)

    {:ok, team} = Team.update(team, %{d4h_refresh_result: status})

    Phoenix.PubSub.broadcast(
      App.PubSub,
      "team_refresh",
      {:team_refreshed, team}
    )
  end
end
