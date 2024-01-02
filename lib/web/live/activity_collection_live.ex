defmodule Web.ActivityCollectionLive do
  use Web, :live_view_app_layout

  alias App.ViewModel.ActivityFilterViewModel

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Activities")}
  end

  def handle_params(params, _uri, socket) do
    case ActivityFilterViewModel.validate(params) do
      {:ok, filter_options, changeset} ->
        current_team = socket.assigns.current_team

        socket =
          socket
          |> assign(:sort, filter_options.sort)
          |> assign(:paginated, build_paginated_content(current_team, filter_options))
          |> assign(:path_fn, build_path_fn(current_team, filter_options))
          |> assign(:form, to_form(changeset, as: "form"))

        {:noreply, socket}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team} />
    <h1 class="title mb-p"><%= @page_title %></h1>
    <.form for={@form} phx-change="change">
      <div class="flex gap-h items-center ">
        <.input field={@form[:q]} label="Search" />
        <.input
          label="Kind"
          field={@form[:activity]}
          type="select"
          options={ActivityFilterViewModel.activity_kinds()}
        />
        <.input
          label="Date"
          field={@form[:date]}
          type="select"
          options={ActivityFilterViewModel.date_kinds()}
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
        <.a navigate={~p"/#{@current_team.subdomain}/activities"}>Reset</.a>
        <span class="text-right grow"><%= @paginated.total_entries %> records</span>
      </div>
    </.form>

    <.table
      id="activity_collection"
      rows={@paginated.entries}
      class="w-full"
      sort={@sort}
      path_fn={@path_fn}
    >
      <:col :let={record} label="Activity" sorts={[{"↓", "id:desc"}, {"↑", "id:asc"}]}>
        <.a navigate={~p"/#{@current_team.subdomain}/activities/#{record.id}"}>
          <.activity_title activity={record} /> #<%= record.ref_id %>
          <%= record.title %>
        </.a>
        <div class="hint break-words">
          <%= Service.StringHelpers.truncate(record.description, max_length: 120) %>
        </div>
        <.activity_tags activity={record} />
      </:col>
      <:col :let={record} label="Kind" class="w-1/12">
        <.activity_badges activity={record} />
      </:col>
      <:col :let={record} label="Date" class="w-1/12" sorts={[{"↓", "date:desc"}, {"↑", "date:asc"}]}>
        <span class="whitespace-nowrap">
          <%= Service.Format.short_date(record.started_at) %>
        </span>
      </:col>
    </.table>

    <.pagination class="my-p" paginated={@paginated} path_fn={@path_fn} />
    """
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    case ActivityFilterViewModel.validate(form_params) do
      {:ok, filter_options, _changeset} ->
        path = build_filter_path(socket.assigns.current_team, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def build_paginated_content(team, filter_options) do
    ActivityFilterViewModel.build_paginated_content(team, filter_options)
  end

  def build_path_fn(team, filter_options) do
    fn changed_options ->
      build_filter_path(team, Map.merge(filter_options, Map.new(changed_options)))
    end
  end

  def build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{team.subdomain}/activities?#{query_params}"
  end
end
