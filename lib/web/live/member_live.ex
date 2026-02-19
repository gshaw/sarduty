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

    records =
      AttendanceFilterViewModel.build_filtered_content(member, filter_options)

    socket =
      socket
      |> assign(:page_title, "#{member.name} - Attendance")
      |> assign(:member, member)
      |> assign(:filter_form, to_form(filter_changeset, as: :filter))
      |> assign(:records, records)

    {:noreply, socket}
  end

  def handle_event("change", params, socket) do
    params = clean_params(params)

    {:ok, filter_options, _} = AttendanceFilterViewModel.validate(params)

    records =
      AttendanceFilterViewModel.build_filtered_content(socket.assigns.member, filter_options)

    member = socket.assigns.member
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    path = ~p"/#{member.team.subdomain}/members/#{member.id}?#{query_params}"

    socket =
      socket
      |> push_patch(to: path, replace: true)
      |> assign(:records, records)

    {:noreply, socket}
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
          records={@records}
          member={@member}
        />
      </main>
    </div>
    """
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
