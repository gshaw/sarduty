defmodule Web.Components.TeamSettingsTabs do
  use Web, :function_component

  # Team settings is one link in the side navigation (#406); its pages are tabs under one
  # title, a topic each: the team and what it has turned on, then its members, who signs
  # its letters and forms, and its activities. Fields, after Members, is what each custom
  # field on its records means (#872). Chore categories shows with chores on, and Agents
  # with Agents on. The key, rarely needed, is Change access key from General (#727).

  attr :team, :map, required: true

  attr :current, :atom,
    required: true,
    values: [
      :general,
      :admins,
      :members,
      :fields,
      :features,
      :signer,
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
      <:tab navigate={~p"/teams/#{@team}/settings/admins"} current={@current == :admins}>
        Admins
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/features"} current={@current == :features}>
        Features
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/members"} current={@current == :members}>
        Members
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/fields"} current={@current == :fields}>
        Fields
      </:tab>
      <:tab navigate={~p"/teams/#{@team}/settings/signer"} current={@current == :signer}>
        Signer
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
      <:tab
        :if={@team.mcp_enabled}
        navigate={~p"/teams/#{@team}/settings/mcp"}
        current={@current == :mcp}
      >
        Agents
      </:tab>
    </.tabs>
    """
  end

  @general ~w(team.name team.legal_name team.abbreviated_name team.mailing_address team.city
              team.postal_code)

  @doc """
  The tab that fills one of the team's values a letter or form reads, by its name, such
  as `team.signer`: General for its names and address, Signer for who signs (#995), or
  nil for one no tab fills.
  """
  def tab_for(name) when name in @general, do: :general
  def tab_for("team.signer" <> _rest), do: :signer
  def tab_for(_name), do: nil

  @doc """
  Where to fill team settings' `tab`, as `tab_for/1` names it: Change team for General's
  names and address (#1076), which General only shows, and the Signer tab.
  """
  def tab_path(team, :general), do: ~p"/teams/#{team}/settings/edit"
  def tab_path(team, :signer), do: ~p"/teams/#{team}/settings/signer"
end
