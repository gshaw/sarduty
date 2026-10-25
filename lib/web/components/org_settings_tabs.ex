defmodule Web.Components.OrgSettingsTabs do
  use Web, :function_component

  # Organization settings is one link in the side navigation (#512); its pages are tabs
  # under one title, as Team settings' are.

  attr :organization, :map, required: true
  attr :current, :atom, required: true, values: [:general, :admins, :hours_tags]

  def org_settings_tabs(assigns) do
    ~H"""
    <h1 class="title">Organization settings</h1>
    <.tabs label="Organization settings">
      <:tab navigate={~p"/orgs/#{@organization}/settings"} current={@current == :general}>
        General
      </:tab>
      <:tab navigate={~p"/orgs/#{@organization}/settings/admins"} current={@current == :admins}>
        Organization admins
      </:tab>
      <:tab
        navigate={~p"/orgs/#{@organization}/settings/hours-tags"}
        current={@current == :hours_tags}
      >
        Hours tags
      </:tab>
    </.tabs>
    """
  end
end
