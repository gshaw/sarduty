defmodule App.Operation.SetTeamLogo do
  @moduledoc """
  A team admin sets or removes the team's logo in its records, D4H or Records (#1075).
  One change set row through App.Operation.ApplyEdit; the image rides beside the row and
  is never kept on it.

  The logo goes as a PNG up to 1024 px, transparency kept: Records keeps it at that size,
  and D4H's PREVIEW is 640. Then SAR Duty saves its own copy at once, as the refresh
  would, so the dashboard, cards, and letters show it without waiting for the night's
  refresh.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Operation.RefreshD4HData

  @side 1024

  @doc "Sets the logo to `bytes`, or removes it for nil. `{:ok, team}` or `{:error, text}`."
  def call(%Team{} = team, bytes, %User{} = user, now) do
    with {:ok, png} <- to_png(bytes),
         {:ok, _d4h_team_id} <- ApplyEdit.call(team, user, plan(team, png), now, logo: png) do
      {:ok, RefreshD4HData.save_logo(team, saved(png), now)}
    end
  end

  def plan(%Team{} = team, nil) do
    %ChangeSetRow{
      action: :remove_team_logo,
      d4h_record_id: team.d4h_team_id,
      old_value: %{},
      new_value: %{}
    }
  end

  def plan(%Team{} = team, png) when is_binary(png) do
    %ChangeSetRow{
      action: :set_team_logo,
      d4h_record_id: team.d4h_team_id,
      old_value: %{},
      new_value: %{"size" => byte_size(png)}
    }
  end

  defp saved(nil), do: :none
  defp saved(png), do: {:ok, png, "team.png"}

  defp to_png(nil), do: {:ok, nil}

  defp to_png(bytes) do
    case Service.Image.png(bytes, @side) do
      {:ok, png} ->
        {:ok, png}

      {:error, _reason} ->
        {:error, "SAR Duty cannot read this logo. Select a JPEG, PNG, or WebP."}
    end
  end
end
