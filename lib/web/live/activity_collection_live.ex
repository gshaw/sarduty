defmodule Web.ActivityCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.Activity
  alias App.Repo
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
          |> assign(:paginated, build_paginated_content(current_team, filter_options))
          |> assign(:paginated_path_fn, build_paginated_path_fn(current_team, filter_options))
          |> assign(:form, to_form(changeset, as: "form"))

        {:noreply, socket}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <div class="mb-p05 text-sm">
      <.a navigate={~p"/#{@current_team.subdomain}"}><%= @current_team.name %></.a>
    </div>
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
          label="Limit"
          field={@form[:limit]}
          type="select"
          options={ActivityFilterViewModel.limits()}
        />
        <.a navigate={~p"/#{@current_team.subdomain}/activities"}>Reset</.a>
        <span class="grow"></span>
        <span class="">
          <%= @paginated.total_entries %> records
        </span>
      </div>
    </.form>

    <.table id="activity_collection" rows={@paginated.entries}>
      <:col :let={record} label="Activity">
        <.a navigate={~p"/#{@current_team.subdomain}/activities/#{record.id}"}>
          <.activity_title activity={record} /> #<%= record.ref_id %>
          <%= record.title %>
        </.a>
        <div class="hint break-words">
          <%= Service.StringHelpers.truncate(record.description, max_length: 120) %>
        </div>
        <.activity_tags activity={record} />
      </:col>
      <:col :let={record} label="Kind">
        <.activity_kind_badge activity={record} />
        <.activity_tracking_number_badge activity={record} />
      </:col>
      <:col :let={record} label="Date">
        <span class="whitespace-nowrap">
          <%= Calendar.strftime(record.started_at, "%x") %>
        </span>
      </:col>
    </.table>

    <.pagination class="my-p" paginated={@paginated} path_fn={@paginated_path_fn} />
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
    Activity
    |> Activity.scope(team_id: team.id)
    |> Activity.scope(activity: filter_options.activity)
    |> Activity.scope(date: filter_options.date)
    |> Activity.scope(q: filter_options.q)
    |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  def build_paginated_path_fn(team, filter_options) do
    fn page_number ->
      build_filter_path(team, Map.put(filter_options, :page, page_number))
    end
  end

  def build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{team.subdomain}/activities?#{query_params}"
  end
end
