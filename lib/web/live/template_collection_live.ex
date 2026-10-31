defmodule Web.TemplateCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.Template

  # Templates: named sets of items with default hours, tags, and groups whose members they
  # add, applied to an activity in one step (#271, #162), for one kind of activity its D4H
  # custom field values (#307), and the details that start an activity (#746).
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    {:ok, assign(socket, page_title: "Templates", templates: Template.get_all(team.id))}
  end

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">{@page_title}</h1>
      <:action>
        <.button id="template-add" navigate={~p"/teams/#{@current_team}/templates/new"}>
          Add template
        </.button>
      </:action>
    </.heading_row>
    <p class="lead">
      A template starts an activity, or adds items, tags, members, and field values to one in one step.
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
      <:col :let={template} label="Kind">
        {Template.kind_label(template)}
      </:col>
      <:col :let={template} label="Start" class="whitespace-nowrap">
        {starts(template)}
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
      <:col :let={template} label="Fields" class="w-px whitespace-nowrap" align="right">
        {map_size(template.custom_values || %{})}
      </:col>
    </.table>

    <.empty_state :if={@templates == []} id="no-templates" title="No templates yet">
      Add one for what goes together, such as the items and tags for boat training.
    </.empty_state>
    """
  end

  # "19:00 · 2h 30m", either half alone, or blank for a template with no details.
  defp starts(template) do
    [
      template.start_time && Service.Format.time_short(template.start_time),
      template.duration_minutes && Service.Format.duration(template.duration_minutes)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end
end
