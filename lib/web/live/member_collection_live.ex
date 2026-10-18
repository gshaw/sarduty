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
      {:ok, filter_options, changeset} ->
        {:noreply, assign_list(socket, filter_options, changeset)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  defp assign_list(socket, filter_options, changeset) do
    current_team = socket.assigns.current_team
    today = Service.Period.today(DateTime.utc_now(), current_team.timezone)

    socket
    |> assign(Map.take(filter_options, [:sort, :status, :details, :attended]))
    |> assign(:today, today)
    |> assign(:standing?, standing_column?(current_team, filter_options, today))
    |> assign(:paginated, build_paginated_content(current_team, filter_options))
    |> assign(:path_fn, build_path_fn(current_team, filter_options))
    |> assign(:form, to_form(changeset, as: "form"))
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
        :if={@standing?}
        field={@form[:standing]}
        label="Standing"
        options={MemberFilterViewModel.standing_kinds(@form[:standing].value)}
        default="any"
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
    <p :if={@attended != "all"} id="attended-hint" class="hint">
      Attended counts from the latest of a member's last activity, the day they joined, the
      end of an away period, and a check-in.
    </p>

    <.table
      id="member_collection"
      rows={@paginated.entries}
      sort={@sort}
      path_fn={@path_fn}
      class="table-striped"
    >
      <:col :let={record} label="ID" class="w-px max-md:hidden" sorts={[{"↑", "id"}]}>
        {record.member.ref_id}
      </:col>
      <:col :let={record} label="Name" class="whitespace-nowrap" sorts={[{"↑", "name"}]}>
        <.a navigate={~p"/teams/#{@current_team}/members/#{record.member.id}"}>
          {record.member.name}
        </.a>
      </:col>
      <:col :let={record} label="Role" sorts={[{"↑", "role"}]}>
        {record.member.position}
      </:col>
      <:col
        :let={record}
        :if={@standing?}
        label="Standing"
        class="whitespace-nowrap"
        sorts={[{"↑", "standing"}, {"↓", "standing-"}]}
      >
        <span id={"standing-#{record.member.id}"}>{standing_text(record, @today)}</span>
      </:col>
      <:col :let={record} :if={@details == "missing"} label="Missing">
        <span id={"missing-#{record.member.id}"}>{missing_text(record.member)}</span>
      </:col>
      <:col
        :let={record}
        :if={@attended != "all"}
        label="Clock starts"
        class="whitespace-nowrap"
      >
        <span id={"clock-starts-#{record.member.id}"}>
          {clock_starts(record, @current_team, @today)}
        </span>
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

  # Shown only when someone on the team is not active, or the filter asks for it.
  defp standing_column?(_team, %{standing: standing}, _today) when standing not in [nil, "any"],
    do: true

  defp standing_column?(team, _filter_options, today),
    do: Member.any_not_active?(team, today, DateTime.utc_now())

  defp standing_text(%{member: %{not_a_person: true}}, _today), do: "Not a person"
  defp standing_text(%{away_until: nil}, _today), do: "Active"

  defp standing_text(%{away_until: until}, today),
    do: "Away until #{Service.Format.day_in_year(until, today)}"

  defp clock_starts(record, team, today) do
    {why, date} = Member.clock_start(record, team.timezone)
    "#{clock_why(why)} #{Service.Format.day_in_year(date, today)}"
  end

  defp clock_why(:attended), do: "Last attended"
  defp clock_why(:checked_in), do: "Checked in"
  defp clock_why(:back), do: "Back from leave"
  defp clock_why(:joined), do: "Joined"

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
