defmodule Web.Components.TeamSettingsTabs do
  use Web, :function_component

  # Team settings is one link in the side navigation (#406); its pages are tabs under one
  # title. Chore categories shows with member logins on, since members log chores. MCP
  # tokens shows once a SAR Duty admin turns MCP on for the team.

  attr :team, :map, required: true

  attr :current, :atom,
    required: true,
    values: [:general, :managers, :member_logins, :hours_tags, :chore_categories, :mcp]

  def team_settings_tabs(assigns) do
    ~H"""
    <h1 class="title">Team settings</h1>
    <.tabs label="Team settings">
      <:tab navigate={~p"/teams/#{@team}/settings"} current={@current == :general}>
        General
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/managers"} current={@current == :managers}>
        Team admins
      </:tab>
      <:tab
        navigate={~p"/teams/#{@team}/settings/member-logins"}
        current={@current == :member_logins}
      >
        Member logins
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/hours-tags"} current={@current == :hours_tags}>
        Hours tags
      </:tab>
      <:tab
        :if={@team.member_logins}
        navigate={~p"/teams/#{@team}/settings/chore-categories"}
        current={@current == :chore_categories}
      >
        Chore categories
      </:tab>
      <:tab
        :if={@team.mcp_enabled}
        navigate={~p"/teams/#{@team}/settings/mcp"}
        current={@current == :mcp}
      >
        MCP tokens
      </:tab>
    </.tabs>
    """
  end
end
