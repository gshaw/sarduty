defmodule Web.Settings.ChoreCategoryCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.Team

  # The team's chore categories (#341), /teams/:subdomain/settings/chore-categories.
  # Only members log chores, so the page exists only with member logins on.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !Team.chores?(team), do: raise(Web.Status.NotFound)

    year = DateTime.utc_now() |> Service.Period.today(team.timezone) |> Map.fetch!(:year)

    socket =
      socket
      |> assign(
        page_title: "Team settings · Chore categories",
        categories: ChoreCategory.get_all(team.id)
      )
      |> assign(year: year, counts: Chore.count_by_category(team.id, year))

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
        Members pick a category when they log a chore. Each send makes one D4H activity for each category and year.
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
      <:col :let={category} label={"Chores in #{@year}"} align="right">
        {Service.Format.number(Map.get(@counts, category.id, 0))}
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
