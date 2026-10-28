defmodule Web.Components.TeamSettingsTabs do
  use Web, :function_component

  # Team settings is one link in the side navigation (#406); its pages are tabs under one
  # title, a topic each, in pairs: the team, its members, its letters, its activities.
  # Chore categories shows with chores on.

  attr :team, :map, required: true

  attr :current, :atom,
    required: true,
    values: [
      :general,
      :team_admins,
      :members,
      :member_logins,
      :tax_credit_letters,
      :hours_tags,
      :places,
      :chore_categories,
      :mcp
    ]

  def team_settings_tabs(assigns) do
    ~H"""
    <h1 class="title">Team settings</h1>
    <.tabs label="Team settings">
      <:tab navigate={~p"/teams/#{@team}/settings"} current={@current == :general}>
        General
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/team-admins"} current={@current == :team_admins}>
        Team admins
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/members"} current={@current == :members}>
        Members
      </:tab>
      <:tab
        navigate={~p"/teams/#{@team}/settings/member-logins"}
        current={@current == :member_logins}
      >
        Member logins
      </:tab>
      <:tab
        navigate={~p"/teams/#{@team}/settings/tax-credit-letters"}
        current={@current == :tax_credit_letters}
      >
        Tax credit letters
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/hours-tags"} current={@current == :hours_tags}>
        Hours tags
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/places"} current={@current == :places}>
        Places
      </:tab>
      <:tab
        :if={App.Model.Team.chores?(@team)}
        navigate={~p"/teams/#{@team}/settings/chore-categories"}
        current={@current == :chore_categories}
      >
        Chore categories
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/mcp"} current={@current == :mcp}>
        MCP tokens
      </:tab>
    </.tabs>
    """
  end
end
