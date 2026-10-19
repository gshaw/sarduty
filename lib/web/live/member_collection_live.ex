defmodule Web.MemberCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.FilterBar

  alias App.Adapter.D4H
  alias App.Model.Member
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
          |> assign(:details, filter_options.details)
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
    <div class="heading-row">
      <h1 class="title">{@page_title}</h1>
      <.button
        :if={D4H.records?(@current_team)}
        id="member-add"
        navigate={~p"/teams/#{@current_team}/members/new"}
      >
        Add member
      </.button>
    </div>
    <.filter_bar
      for={@form}
      id="member_filter_form"
      count={Service.Format.count(@paginated.total_entries, one: "%d member", many: "%d members")}
      clear={@path_fn.(:reset)}
      path_fn={@path_fn}
      page={@paginated}
      hidden={[@form[:sort]]}
    >
      <:search field={@form[:q]} />
      <:filter
        field={@form[:status]}
        label="Status"
        options={MemberFilterViewModel.status_kinds()}
        default="active"
      />
      <:filter
        field={@form[:when]}
        label="Period"
        options={MemberFilterViewModel.when_kinds(@current_team)}
        default={MemberFilterViewModel.current_year()}
      />
      <:filter
        field={@form[:group]}
        label="Group"
        type="combobox"
        options={MemberFilterViewModel.group_kinds(@current_team)}
        default=""
      />
      <:filter
        field={@form[:details]}
        label="Details"
        options={MemberFilterViewModel.details_kinds()}
        default="all"
      />
      <:filter
        field={@form[:attended]}
        label="Attended"
        options={MemberFilterViewModel.attended_kinds()}
        default="all"
      />
    </.filter_bar>

    <.table
      id="member_collection"
      rows={@paginated.entries}
      sort={@sort}
      path_fn={@path_fn}
      class="table-striped"
    >
      <:col :let={record} label="ID" class="w-px" sorts={[{"↑", "id"}]}>
        {record.member.ref_id}
      </:col>
      <:col :let={record} label="Name" sorts={[{"↑", "name"}]}>
        <.a navigate={~p"/teams/#{@current_team}/members/#{record.member.id}"}>
          {record.member.name}
        </.a>
      </:col>
      <:col :let={record} label="Role" class="w-1/3" sorts={[{"↑", "role"}]}>
        {record.member.position}
      </:col>
      <:col :let={record} :if={@details == "missing"} label="Missing">
        <span id={"missing-#{record.member.id}"}>{missing_text(record.member)}</span>
      </:col>
      <:col
        :let={record}
        label="Last attended"
        align="right"
        class="w-1/12 whitespace-nowrap"
        sorts={[{"↑", "attended"}, {"↓", "attended-"}]}
      >
        <span id={"last-attended-#{record.member.id}"}>
          {last_attended(record.last_attended_at, @current_team)}
        </span>
      </:col>
      <:col
        :let={record}
        label="Activities"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "activities-"}, {"↑", "activities"}]}
      >
        {record.activity_count}
      </:col>
      <:col
        :let={record}
        label="Duration"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "duration-"}, {"↑", "duration"}]}
      >
        {Service.Format.duration(record.total_minutes)}
      </:col>
      <:col
        :let={record}
        label="Joined"
        align="right"
        class="w-1/12 whitespace-nowrap"
        sorts={[{"↓", "date-"}, {"↑", "date"}]}
      >
        {Service.Format.date_short(record.member.joined_at, @current_team.timezone)}
      </:col>
      <:col
        :let={record}
        :if={@status != "active"}
        label="Departed"
        align="right"
        class="w-1/12 whitespace-nowrap"
        sorts={[{"↓", "departed-"}, {"↑", "departed"}]}
      >
        {Service.Format.date_short(record.member.left_at, @current_team.timezone)}
      </:col>
    </.table>

    <.pagination class="my-4" paginated={@paginated} path_fn={@path_fn} />
    """
  end

  defp last_attended(nil, _team), do: "Never"
  defp last_attended(started_at, team), do: Service.Format.date_short(started_at, team.timezone)

  defp missing_text(member) do
    member
    |> Member.missing_details()
    |> Enum.map_join(", ", &missing_label/1)
  end

  defp missing_label(:mobile_phone), do: "Mobile phone"
  defp missing_label(:email), do: "Email"

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
    ~p"/teams/#{team}/members?#{query_params}"
  end
end
