defmodule Web.Components.ActivitiesTabs do
  use Web, :function_component

  # Activities, Templates, and Proposed changes are tabs on the Activities page for team
  # admins (#406). Proposed changes come from AI agents through MCP, a trial most teams
  # don't have: the tab shows only when the team has it, or something waits there, with
  # the count in an amber tag.

  attr :team, :map, required: true
  attr :current, :atom, required: true, values: [:activities, :templates, :proposed_changes]
  attr :proposed_changes, :integer, default: 0

  def activities_tabs(assigns) do
    ~H"""
    <.tabs label="Activities">
      <:tab navigate={~p"/teams/#{@team}/activities"} current={@current == :activities}>
        Activities
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/templates"} current={@current == :templates}>
        Templates
      </:tab>
      <:tab
        :if={@team.mcp_enabled or @proposed_changes > 0}
        navigate={~p"/teams/#{@team}/proposed-changes"}
        current={@current == :proposed_changes}
      >
        Proposed changes
        <.badge :if={@proposed_changes > 0} kind={:warning}>{@proposed_changes}</.badge>
      </:tab>
    </.tabs>
    """
  end
end
