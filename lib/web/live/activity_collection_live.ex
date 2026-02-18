defmodule Web.ActivityCollectionLive do
  use Web, :live_view_app_layout

  alias App.ViewModel.ActivityFilterViewModel

  def mount(_params, _session, socket) do
    {:ok, socket}
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

    <h1 class="title mb-p">Activities</h1>

    <.activity_filter_table
      form={@form}
      paginated={@paginated}
      sort={@sort}
      path_fn={@path_fn}
      team={@current_team}
    />
    """
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    case ActivityFilterViewModel.validate(form_params) do
      {:ok, filter_options, _changeset} ->
        current_team = socket.assigns.current_team
        path = build_filter_path(current_team, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _changeset} ->
        raise Web.Status.NotFound
    end
  end

  def build_paginated_content(team, filter_options) do
    ActivityFilterViewModel.build_paginated_content(team, nil, filter_options)
  end

  def build_path_fn(team, filter_options) do
    fn changed_options ->
      case changed_options do
        :future ->
          build_filter_path(team, %ActivityFilterViewModel{when: "future", sort: "date"})

        :past ->
          build_filter_path(team, %ActivityFilterViewModel{when: "past", sort: "date-"})

        :all ->
          build_filter_path(team, %ActivityFilterViewModel{})

        _ ->
          build_filter_path(team, Map.merge(filter_options, Map.new(changed_options)))
      end
    end
  end

  def build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{team.subdomain}/activities?#{query_params}"
  end
end
