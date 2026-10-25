defmodule Web.ActivityCollectionLive do
  use Web, {:live_view_app_layout, access: :team, member_events: ["change"]}

  import Web.Components.ActivityFilterTable

  alias App.Adapter.D4H
  alias App.ViewModel.ActivityFilterViewModel

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Activities")}
  end

  # Members open it too (#406) and get the same list, filters, and default as a team
  # admin. Team admins also get Add activity and the Templates and Proposed changes tabs.
  def handle_params(params, _uri, socket) do
    case ActivityFilterViewModel.validate(params) do
      # credo:disable-for-next-line
      {:ok, filter_options, changeset} ->
        current_team = socket.assigns.current_team

        socket =
          socket
          |> assign(:sort, filter_options.sort)
          |> assign(:when, filter_options.when)
          |> assign(:paginated, build_paginated_content(socket.assigns, filter_options))
          |> assign(
            :kind_counts,
            ActivityFilterViewModel.kind_counts(current_team, nil, filter_options)
          )
          |> assign(:path_fn, build_path_fn(current_team, filter_options))
          |> assign(:form, to_form(changeset, as: "form"))

        {:noreply, socket}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">Activities</h1>
      <:action>
        <.button
          :if={@team_admin? and D4H.records?(@current_team)}
          id="activity-add"
          navigate={~p"/teams/#{@current_team}/activities/new"}
        >
          Add activity
        </.button>
      </:action>
    </.heading_row>

    <.activity_filter_table
      form={@form}
      paginated={@paginated}
      sort={@sort}
      path_fn={@path_fn}
      team={@current_team}
      kind_counts={@kind_counts}
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

  # Picking Past or Future also picks the sort, so Future doesn't open on next year.
  defp sort_for_new_when(%{"when" => new_when} = form_params, old_when)
       when new_when != old_when do
    case ActivityFilterViewModel.sort_for_when(new_when) do
      nil -> form_params
      sort -> Map.put(form_params, "sort", sort)
    end
  end

  defp sort_for_new_when(form_params, _old_when), do: form_params

  defp build_paginated_content(%{current_team: team}, filter_options),
    do: ActivityFilterViewModel.build_paginated_content(team, nil, filter_options)

  def build_path_fn(team, filter_options) do
    fn
      :all ->
        build_filter_path(team, %ActivityFilterViewModel{})

      changed_options ->
        build_filter_path(team, Map.merge(filter_options, Map.new(changed_options)))
    end
  end

  def build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/teams/#{team}/activities?#{query_params}"
  end
end
