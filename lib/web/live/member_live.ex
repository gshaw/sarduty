defmodule Web.MemberLive do
  use Web, :live_view_app_layout

  import Web.Components.AttendanceFilterTable
  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Model.Member
  alias App.Repo
  alias App.ViewModel.AttendanceFilterViewModel

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = find_member(params["id"])

    {:ok, filter_options, filter_changeset} =
      AttendanceFilterViewModel.validate(params)

    paginated =
      AttendanceFilterViewModel.build_paginated_content(member, filter_options)

    total_minutes =
      AttendanceFilterViewModel.total_duration(member, filter_options)

    socket =
      socket
      |> assign(:page_title, "#{member.name} - Attendance")
      |> assign(:member, member)
      |> assign(:filter_form, to_form(filter_changeset, as: :filter))
      |> assign(:paginated, paginated)
      |> assign(:total_minutes, total_minutes)
      |> assign(:sort, filter_options.sort)
      |> assign(:path_fn, build_path_fn(member, filter_options))

    {:noreply, socket}
  end

  def handle_event("change", params, socket) do
    params = clean_params(params)

    {:ok, filter_options, _} = AttendanceFilterViewModel.validate(params)

    member = socket.assigns.member
    path = build_filter_path(member, filter_options)

    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Members" path={~p"/#{@current_team.subdomain}/members/"} />
      <:item label={@member.ref_id} />
      <:item label="Attendance" />
    </.breadcrumbs>

    <h1 class="title">{@member.name}</h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content member={@member} />
      </aside>
      <main class="content-2/3">
        <.member_tabs member={@member} active_tab={:attendance} />
        <.attendance_filter_table
          form={@filter_form}
          paginated={@paginated}
          total_minutes={@total_minutes}
          sort={@sort}
          path_fn={@path_fn}
          member={@member}
        />
      </main>
    </div>
    """
  end

  defp build_path_fn(member, filter_options) do
    fn
      :reset ->
        build_filter_path(member, %AttendanceFilterViewModel{})

      changed_options ->
        build_filter_path(member, Map.merge(filter_options, Map.new(changed_options)))
    end
  end

  defp build_filter_path(member, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{member.team.subdomain}/members/#{member.id}?#{query_params}"
  end

  defp find_member(member_id) do
    Member
    |> Repo.get(member_id)
    |> Repo.preload([:team])
  end

  defp clean_params(params) do
    case params do
      %{"filter" => filter} -> filter
      %{} -> %{}
    end
  end
end
