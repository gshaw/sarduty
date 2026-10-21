defmodule Web.Settings.ChoreCategoryCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.ChoreCategory

  # The team's chore categories (#341), /teams/:subdomain/settings/chore-categories.
  # Members log chores in their member area, so the page exists only with member logins on.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !team.member_logins, do: raise(Web.Status.NotFound)

    socket =
      assign(socket,
        page_title: "Team settings · Chore categories",
        categories: ChoreCategory.get_all(team.id)
      )

    {:ok, socket}
  end

  @doc "How a category's hours read."
  def hours_label(:primary), do: "Primary"
  def hours_label(:secondary), do: "Secondary"

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:chore_categories} />
    <div class="heading-row">
      <p class="lead measure">
        Members pick a category when they log a chore. Each month, each category is its own D4H event.
      </p>
      <.button
        id="chore-category-add"
        variant={:success}
        navigate={~p"/teams/#{@current_team}/settings/chore-categories/new"}
      >
        Add category
      </.button>
    </div>

    <.table
      :if={@categories != []}
      id="chore-categories"
      rows={@categories}
      row_id={&"chore-category-#{&1.id}"}
      class="table-striped table-stack"
    >
      <:col :let={category} label="Category" class="stack-title">
        <.a navigate={~p"/teams/#{@current_team}/settings/chore-categories/#{category.id}"}>
          {category.title}
        </.a>
      </:col>
      <:col :let={category} label="SARVAC hours">{hours_label(category.hours)}</:col>
      <:col :let={category} label="Other tags">
        <span class="badges">
          <.badge :for={tag <- ChoreCategory.tags(category)} kind={:outline}>{tag.title}</.badge>
        </span>
      </:col>
      <:col :let={category} label="" class="stack-optional w-px whitespace-nowrap">
        <.badge :if={ChoreCategory.archived?(category)}>Archived</.badge>
      </:col>
    </.table>

    <.empty_state :if={@categories == []} id="no-chore-categories" title="No chore categories yet">
      Add one for each kind of chore your team counts, such as equipment maintenance.
    </.empty_state>
    """
  end
end
