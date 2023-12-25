defmodule Web.MemberCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.Member
  alias App.Repo
  alias App.ViewModel.MemberFilterViewModel

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Members")}
  end

  def handle_params(params, _uri, socket) do
    case MemberFilterViewModel.validate(params) do
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
          label="Sort"
          field={@form[:order]}
          type="select"
          options={MemberFilterViewModel.order_kinds()}
        />
        <.input
          label="Limit"
          field={@form[:limit]}
          type="select"
          options={MemberFilterViewModel.limits()}
        />
        <.a navigate={~p"/#{@current_team.subdomain}/members"}>Reset</.a>
        <span class="text-right grow"><%= @paginated.total_entries %> records</span>
      </div>
    </.form>

    <.table id="member_collection" rows={@paginated.entries} class="w-full">
      <:col :let={record} label="Member">
        <.a navigate={~p"/#{@current_team.subdomain}/members/#{record.id}"}>
          <%= record.name %>
        </.a>
      </:col>
      <:col :let={record} label="Role" class="w-1/3">
        <%= record.position %>
      </:col>
      <:col :let={record} label="Joined" class="w-1/12">
        <span class="whitespace-nowrap">
          <%= Calendar.strftime(record.joined_at, "%x") %>
        </span>
      </:col>
    </.table>

    <.pagination class="my-p" paginated={@paginated} path_fn={@paginated_path_fn} />
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
    Member
    |> Member.scope(team_id: team.id)
    |> Member.scope(q: filter_options.q)
    |> Member.scope(order: filter_options.order)
    |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  def build_paginated_path_fn(team, filter_options) do
    fn page_number ->
      build_filter_path(team, Map.put(filter_options, :page, page_number))
    end
  end

  def build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{team.subdomain}/members?#{query_params}"
  end
end
