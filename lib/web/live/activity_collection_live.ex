defmodule Web.ActivityCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.Member
  alias App.Repo
  alias App.ViewModel.ActivityFilterViewModel

  def mount(params, _session, socket) do
    member = find_member(params["member_id"])

    socket =
      socket
      |> assign(:member, member)
      |> assign(:page_title, build_page_title(member))

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    case ActivityFilterViewModel.validate(params) do
      {:ok, filter_options, changeset} ->
        current_team = socket.assigns.current_team
        member = socket.assigns.member

        socket =
          socket
          |> assign(:sort, filter_options.sort)
          |> assign(:paginated, build_paginated_content(current_team, member, filter_options))
          |> assign(:path_fn, build_path_fn(current_team, member, filter_options))
          |> assign(:form, to_form(changeset, as: "form"))

        {:noreply, socket}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <%= if @member do %>
      <.breadcrumbs team={@current_team}>
        <:item label="Members" path={~p"/#{@member.team.subdomain}/members/"} />
        <:item
          label={"##{@member.ref_id} #{@member.name}"}
          path={~p"/#{@member.team.subdomain}/members/#{@member.id}"}
        />
        <:item label="Activities" />
      </.breadcrumbs>
    <% else %>
      <.breadcrumbs team={@current_team} />
    <% end %>

    <h1 class="title mb-p"><%= @page_title %></h1>
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
        member = socket.assigns.member
        path = build_filter_path(current_team, member, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _changeset} ->
        raise Web.Status.NotFound
    end
  end

  def build_page_title(nil), do: "Activities"
  def build_page_title(member), do: "#{member.name}’s Activities"

  def find_member(nil), do: nil

  def find_member(member_id) do
    member_id
    |> Member.get()
    |> Repo.preload(:team)
  end

  def build_paginated_content(team, member, filter_options) do
    ActivityFilterViewModel.build_paginated_content(team, member, filter_options)
  end

  def build_path_fn(team, member, filter_options) do
    fn changed_options ->
      case changed_options do
        :reset -> build_filter_path(team, member, %ActivityFilterViewModel{})
        _ -> build_filter_path(team, member, Map.merge(filter_options, Map.new(changed_options)))
      end
    end
  end

  def build_filter_path(team, nil, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{team.subdomain}/activities?#{query_params}"
  end

  def build_filter_path(team, member, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{team.subdomain}/members/#{member.id}/activities?#{query_params}"
  end
end
