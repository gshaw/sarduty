defmodule Web.TemplateCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.Template

  # Templates: named sets of items with default hours, tags, and groups to invite, added
  # to an activity in one step (#271, #162).
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    {:ok, assign(socket, page_title: "Templates", templates: Template.get_all(team.id))}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Templates" />
    </.breadcrumbs>
    <div class="heading-row">
      <h1 class="title">{@page_title}</h1>
      <.button id="template-add" navigate={~p"/teams/#{@current_team}/templates/new"}>
        Add template
      </.button>
    </div>
    <p class="lead">
      A template adds items, tags, and invites to an activity in one step. Apply one from the activity's page.
    </p>

    <.table
      :if={@templates != []}
      id="template_collection"
      rows={@templates}
      row_id={&"template-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={template} label="Template">
        <.a navigate={~p"/teams/#{@current_team}/templates/#{template.id}"}>{template.title}</.a>
      </:col>
      <:col :let={template} label="Items" class="w-px whitespace-nowrap" align="right">
        {length(template.template_items)}
      </:col>
      <:col :let={template} label="Tags" class="w-px whitespace-nowrap" align="right">
        {length(template.template_tags)}
      </:col>
      <:col :let={template} label="Groups" class="w-px whitespace-nowrap" align="right">
        {length(template.template_groups)}
      </:col>
    </.table>

    <.empty_state :if={@templates == []} id="no-templates" title="No templates yet">
      Add one for what goes together, such as a boat training's gear and tags.
    </.empty_state>
    """
  end
end
