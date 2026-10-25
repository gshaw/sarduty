defmodule Web.Components.TeamRefresh do
  @moduledoc """
  How a team's refresh reads in a list of teams (#512, #513): OK, Never refreshed, or
  "Not refreshed since" the last good refresh. SAR Duty doesn't store when failures
  began, so it never says "failing since".
  """
  use Web, :function_component

  alias App.Model.Team

  @doc "`:ok`, `:never`, or `:failed`: a refresh in progress reads as its last result."
  def state(%Team{} = team) do
    case Team.refresh_state(team.d4h_refresh_result) do
      :refreshing -> if team.d4h_refreshed_at, do: :ok, else: :never
      state -> state
    end
  end

  @doc "Whether the team is not refreshing: it failed or never refreshed."
  def not_refreshing?(%Team{} = team), do: state(team) != :ok

  attr :team, :map, required: true
  attr :id, :string, default: nil

  def team_refresh(assigns) do
    assigns = assign(assigns, :state, state(assigns.team))

    ~H"""
    <span :if={@state == :ok} id={@id} class="text-success-text">OK</span>
    <span :if={@state == :never} id={@id} class="text-danger-text">Never refreshed</span>
    <span :if={@state == :failed} id={@id} class="text-danger-text">
      {not_refreshed_since(@team)}
    </span>
    """
  end

  @doc ~s("Not refreshed since Oct 3, 2026", or "Never refreshed" when it never did.)
  def not_refreshed_since(%Team{d4h_refreshed_at: nil}), do: "Never refreshed"

  def not_refreshed_since(%Team{} = team),
    do: "Not refreshed since #{Service.Format.date_short(team.d4h_refreshed_at, team.timezone)}"
end
