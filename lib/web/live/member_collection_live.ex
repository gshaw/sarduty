defmodule Web.MemberCollectionLive do
  use Web, :live_view_app_layout

  alias App.ViewModel.MemberFilterViewModel

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Members")}
  end

  def handle_params(params, _uri, socket) do
    case MemberFilterViewModel.validate(params) do
      # credo:disable-for-next-line
      {:ok, filter_options, changeset} ->
        current_team = socket.assigns.current_team

        socket =
          socket
          |> assign(:sort, filter_options.sort)
          |> assign(:status, filter_options.status)
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
    <h1 class="title mb-p">{@page_title}</h1>
    <.form for={@form} phx-change="change" phx-submit="change" class="filter-form">
      <.input field={@form[:q]} label="Search" />
      <.input
        label="Status"
        field={@form[:status]}
        type="select"
        options={MemberFilterViewModel.status_kinds()}
      />
      <.input
        label="Sort"
        field={@form[:sort]}
        type="select"
        options={MemberFilterViewModel.sort_kinds()}
      />
      <.input
        label="Limit"
        field={@form[:limit]}
        type="select"
        options={MemberFilterViewModel.limits()}
      />
    </.form>

    <div class="filter-form-results">
      {Service.Format.count(@paginated.total_entries, one: "%d member", many: "%d members")} ·
      <.a navigate={@path_fn.(:reset)}>Reset</.a>
    </div>

    <.table
      id="member_collection"
      rows={@paginated.entries}
      sort={@sort}
      path_fn={@path_fn}
      class="w-full table-striped"
    >
      <:col :let={record} label="ID" class="w-px" sorts={[{"↑", "id"}]}>
        {record.ref_id}
      </:col>
      <:col :let={record} label="Name" sorts={[{"↑", "name"}]}>
        <.a navigate={~p"/#{@current_team.subdomain}/members/#{record.id}"}>
          {record.name}
        </.a>
      </:col>
      <:col :let={record} label="Role" class="w-1/3" sorts={[{"↑", "role"}]}>
        {record.position}
      </:col>
      <:col :let={record} label="Joined" class="w-1/12" sorts={[{"↓", "date-"}, {"↑", "date"}]}>
        <span class="label md:hidden">Joined</span>
        <span class="whitespace-nowrap">
          {Service.Format.date_short(record.joined_at, @current_team.timezone)}
        </span>
      </:col>
      <:col
        :let={record}
        :if={@status != "active"}
        label="Departed"
        class="w-1/12"
        sorts={[{"↓", "departed-"}, {"↑", "departed"}]}
      >
        <span class="label md:hidden">Departed</span>
        <span :if={record.left_at} class="whitespace-nowrap">
          {Service.Format.date_short(record.left_at, @current_team.timezone)}
        </span>
        <span :if={!record.left_at} class="text-gray-400">-</span>
      </:col>
    </.table>

    <.pagination class="my-p" paginated={@paginated} path_fn={@path_fn} />
    """
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    case MemberFilterViewModel.validate(form_params) do
      {:ok, filter_options, _changeset} ->
        path = build_filter_path(socket.assigns.current_team, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def build_paginated_content(team, filter_options) do
    MemberFilterViewModel.build_paginated_content(team, filter_options)
  end

  def build_path_fn(team, filter_options) do
    fn changed_options ->
      case changed_options do
        :reset ->
          build_filter_path(team, %MemberFilterViewModel{})

        _ ->
          build_filter_path(team, Map.merge(filter_options, Map.new(changed_options)))
      end
    end
  end

  def build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{team.subdomain}/members?#{query_params}"
  end
end
