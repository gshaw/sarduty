defmodule Web.Components.ActivityFilterTable do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H
  import Web.Components.Pagination
  import Web.Components.Table

  alias App.ViewModel.ActivityFilterViewModel

  attr :form, :map, required: true
  attr :paginated, :map, required: true
  attr :sort, :map, required: true
  attr :path_fn, :map, required: true
  attr :team, :map, required: true

  def activity_filter_table(assigns) do
    ~H"""
    <.form for={@form} phx-change="change" class="filter-form">
      <.input field={@form[:q]} label="Search" />
      <.input
        label="Kind"
        field={@form[:activity]}
        type="select"
        options={ActivityFilterViewModel.activity_kinds()}
      />
      <.input
        label="When"
        field={@form[:when]}
        type="select"
        options={ActivityFilterViewModel.when_kinds()}
      />
      <.input
        label="Sort"
        field={@form[:sort]}
        type="select"
        options={ActivityFilterViewModel.sort_kinds()}
      />
      <.input
        label="Limit"
        field={@form[:limit]}
        type="select"
        options={ActivityFilterViewModel.limits()}
      />
      <.a class="filter-form-reset" navigate={@path_fn.(:reset)}>Reset</.a>
      <span class="filter-form-count"><%= @paginated.total_entries %> records</span>
    </.form>

    <.table
      id="activity_collection"
      rows={@paginated.entries}
      class="w-full table-striped"
      sort={@sort}
      path_fn={@path_fn}
    >
      <:col :let={record} label="Activity" sorts={[{"↓", "id-"}, {"↑", "id"}]}>
        <.a navigate={~p"/#{@team.subdomain}/activities/#{record.id}"}>
          <.activity_title activity={record} />
        </.a>
        <div class="hint">
          <%= Service.StringHelpers.truncate(record.description, max_length: 120) %>
        </div>
        <.activity_tags activity={record} />
      </:col>
      <:col :let={record} label="Kind" class="w-1/12">
        <span class="label md:hidden">Kind</span>
        <.activity_badges activity={record} />
      </:col>
      <:col :let={record} label="Date" class="w-1/12" sorts={[{"↓", "date-"}, {"↑", "date"}]}>
        <span class="label md:hidden">Date</span>
        <span class="whitespace-nowrap">
          <%= Service.Format.short_datetime(record.started_at, @team.timezone) %>
        </span>
      </:col>
    </.table>

    <.pagination class="my-p" paginated={@paginated} path_fn={@path_fn} />
    """
  end
end
