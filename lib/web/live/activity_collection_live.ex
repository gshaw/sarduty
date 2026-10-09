defmodule Web.ActivityCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.ActivityFilterTable

  alias App.Adapter.D4H
  alias App.ViewModel.ActivityFilterViewModel

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Activities")}
  end

  def handle_params(params, _uri, socket) do
    case ActivityFilterViewModel.validate(params) do
      # credo:disable-for-next-line
      {:ok, filter_options, changeset} ->
        current_team = socket.assigns.current_team

        socket =
          socket
          |> assign(:sort, filter_options.sort)
          |> assign(:when, filter_options.when)
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

    <div class="heading-row">
      <h1 class="title">Activities</h1>
      <.button
        :if={D4H.hosted?(@current_team)}
        id="activity-add"
        navigate={~p"/teams/#{@current_team}/activities/new"}
        size={:sm}
      >
        Add activity
      </.button>
    </div>

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
    form_params = sort_for_new_when(form_params, socket.assigns.when)

    case ActivityFilterViewModel.validate(form_params) do
      {:ok, filter_options, _changeset} ->
        current_team = socket.assigns.current_team
        path = build_filter_path(current_team, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _changeset} ->
        raise Web.Status.NotFound
    end
  end

  # Picking Past or Future from the menu also picks the sort, as the links do,
  # so Future doesn't open on next year.
  defp sort_for_new_when(%{"when" => new_when} = form_params, old_when)
       when new_when != old_when do
    case ActivityFilterViewModel.sort_for_when(new_when) do
      nil -> form_params
      sort -> Map.put(form_params, "sort", sort)
    end
  end

  defp sort_for_new_when(form_params, _old_when), do: form_params

  def build_paginated_content(team, filter_options) do
    ActivityFilterViewModel.build_paginated_content(team, nil, filter_options)
  end

  def build_path_fn(team, filter_options) do
    fn changed_options ->
      case changed_options do
        when_link when when_link in [:current, :future, :past] ->
          when_name = Atom.to_string(when_link)
          sort = ActivityFilterViewModel.sort_for_when(when_name)
          build_filter_path(team, %ActivityFilterViewModel{when: when_name, sort: sort})

        :all ->
          build_filter_path(team, %ActivityFilterViewModel{})

        _ ->
          build_filter_path(team, Map.merge(filter_options, Map.new(changed_options)))
      end
    end
  end

  def build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/teams/#{team}/activities?#{query_params}"
  end
end
