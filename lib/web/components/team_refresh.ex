defmodule Web.Components.TeamRefresh do
  @moduledoc """
  How a team's refresh reads in a list of teams (#512, #513): OK, Never refreshed, or
  "Not refreshed since" the last good refresh. SAR Duty doesn't store when failures
  began, so it never says "failing since".
  """
  use Web, :function_component

  alias App.Adapter.D4H
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

  @doc """
  Whose access key the team uses, for SAR Duty admin pages (#513): `:none`, `:sar_duty`
  (a D4H account set up for SAR Duty), `:records` (Records names the key itself), or
  `{:person, name}`, a key that stops working when that person leaves, or `:unknown`
  before a refresh has read whose it is.
  """
  def key_kind(%Team{d4h_access_key: key}) when key in [nil, ""], do: :none

  def key_kind(%Team{} = team) do
    cond do
      D4H.records?(team) -> :records
      team.d4h_access_key_owner == nil -> :unknown
      Team.key_owner_is_sar_duty?(team) -> :sar_duty
      true -> {:person, team.d4h_access_key_owner}
    end
  end

  attr :team, :map, required: true
  attr :id, :string, default: nil

  @doc "The key in a few words: None, SAR Duty, SAR Duty Records, or Person's: name."
  def team_key(assigns) do
    assigns = assign(assigns, :kind, key_kind(assigns.team))

    ~H"""
    <span :if={@kind == :none} id={@id} class="text-danger-text">None</span>
    <span :if={@kind == :sar_duty} id={@id}>SAR Duty</span>
    <span :if={@kind == :records} id={@id}>SAR Duty Records</span>
    <span :if={@kind == :unknown} id={@id}>Owner not known yet</span>
    <span :if={match?({:person, _name}, @kind)} id={@id}>Person's: {elem(@kind, 1)}</span>
    """
  end
end
