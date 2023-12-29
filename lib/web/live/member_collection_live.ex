defmodule Web.MemberCollectionLive do
  use Web, :live_view_app_layout

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
          |> assign(:sort, filter_options.sort)
          |> assign(:year, filter_options.year)
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
    <.form for={@form} phx-change="change" phx-submit="change">
      <div class="flex gap-h items-center ">
        <.input
          label="Year"
          field={@form[:year]}
          type="select"
          options={MemberFilterViewModel.years()}
        />
        <.input field={@form[:q]} label="Search" />
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
        <.a navigate={~p"/#{@current_team.subdomain}/members"}>Reset</.a>
        <span class="text-right grow"><%= @paginated.total_entries %> records</span>
      </div>
    </.form>

    <.table
      id="member_collection"
      rows={@paginated.entries}
      sort={@sort}
      path_fn={@path_fn}
      class="w-full"
    >
      <:col
        :let={record}
        label="ID"
        class="w-px"
        align="right"
        sorts={[{"↓", "id:desc"}, {"↑", "id:asc"}]}
      >
        <%= record.member.ref_id %>
      </:col>
      <:col :let={record} label="Name" sorts={[{"↑", "name"}]}>
        <.a navigate={~p"/#{@current_team.subdomain}/members/#{record.member.id}"}>
          <%= record.member.name %>
        </.a>
      </:col>
      <:col :let={record} label="Role" class="w-1/3" sorts={[{"↑", "role"}]}>
        <%= record.member.position %>
      </:col>

      <:col
        :let={record}
        label="Activities"
        class="w-px"
        align="right"
        sorts={[{"↓", "count:desc"}, {"↑", "count:asc"}]}
      >
        <%= record.count %>
      </:col>

      <:col
        :let={record}
        label="Hours"
        class="w-px"
        align="right"
        sorts={[{"↓", "hours:desc"}, {"↑", "hours:asc"}]}
      >
        <%= record.hours %>
      </:col>
      <:col
        :let={record}
        label="Joined"
        class="w-1/12"
        sorts={[{"↓", "date:desc"}, {"↑", "date:asc"}]}
      >
        <span class="whitespace-nowrap">
          <%= Calendar.strftime(record.member.joined_at, "%x") %>
        </span>
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
    MemberFilterViewModel.build_paginated_content(
      team,
      filter_options,
      # []
      # ["AdventureSmart"]
      ["Primary Hours", "Secondary Hours"]
    )
  end

  def build_path_fn(team, filter_options) do
    fn changed_options ->
      build_filter_path(team, Map.merge(filter_options, Map.new(changed_options)))
    end
  end

  def build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{team.subdomain}/members?#{query_params}"
  end
end
