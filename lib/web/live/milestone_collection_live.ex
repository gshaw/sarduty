defmodule Web.MilestoneCollectionLive do
  @moduledoc """
  The team's milestones (#389), for team admins: who reached what, newest first. Opens on
  the last 90 days, for thanking people at a meeting or in a newsletter. A member's
  sidebar links here filtered to them, over all time. Members see only their own, on Your
  membership.
  """

  use Web, :live_view_app_layout

  import Web.Components.FilterBar

  alias App.ViewData.MemberMilestones
  alias App.ViewModel.MilestoneFilterViewModel
  alias Service.Format
  alias Web.Components.MilestoneList

  # Worked out once for the page; the filters only pick from them.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()

    {:ok,
     assign(socket,
       page_title: "Milestones",
       now: now,
       milestones: MemberMilestones.for_team(team, now)
     )}
  end

  def handle_params(params, _uri, socket) do
    case MilestoneFilterViewModel.validate(params) do
      {:ok, filter_options, changeset} ->
        %{current_team: team, milestones: milestones, now: now} = socket.assigns
        shown = MilestoneFilterViewModel.filter(milestones, filter_options, team.timezone, now)

        {:noreply,
         assign(socket,
           filter_options: filter_options,
           form: to_form(changeset, as: "form"),
           paginated: MilestoneFilterViewModel.page(shown, filter_options.page),
           path_fn: build_path_fn(team, filter_options)
         )}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">{@page_title}</h1>

    <.filter_bar
      for={@form}
      id="milestone_filter_form"
      count={Format.count(@paginated.total_entries, one: "%d milestone", many: "%d milestones")}
      clear={@path_fn.(:reset)}
      path_fn={@path_fn}
      page={@paginated}
    >
      <:filter
        field={@form[:member]}
        label="Member"
        type="combobox"
        options={MilestoneFilterViewModel.member_kinds(@milestones)}
        default=""
      />
      <:filter
        field={@form[:kind]}
        label="Kind"
        options={MilestoneFilterViewModel.kinds()}
        default=""
      />
      <:filter
        field={@form[:when]}
        label="Period"
        options={MilestoneFilterViewModel.when_kinds(@milestones)}
        default={MilestoneFilterViewModel.default_when()}
      />
    </.filter_bar>

    <.table
      :if={@paginated.entries != []}
      id="milestones"
      rows={@paginated.entries}
      row_id={&"milestones-#{&1.member.id}-#{&1.kind}-#{&1.count}"}
      class="table-striped"
    >
      <:col :let={milestone} label="Date" class="w-px whitespace-nowrap">
        {Format.date_short(milestone.on)}
      </:col>
      <:col :let={milestone} label="Member" class="whitespace-nowrap">
        <.a navigate={~p"/teams/#{@current_team}/members/#{milestone.member.id}"}>
          {milestone.member.name}
        </.a>
      </:col>
      <:col :let={milestone} label="Milestone" class="whitespace-nowrap">
        {MilestoneList.title(milestone)}
      </:col>
      <:col :let={milestone} label="Activity" class="max-md:hidden">
        <.a
          :if={milestone.activity}
          navigate={~p"/teams/#{@current_team}/activities/#{milestone.activity.id}"}
        >
          {milestone.activity.title}
        </.a>
      </:col>
    </.table>
    <.pagination class="my-4" paginated={@paginated} path_fn={@path_fn} />

    <.empty_state
      :if={@paginated.entries == []}
      id="no-milestones"
      title="No milestones match"
    >
      Change the filters, or pick All under Period.
    </.empty_state>
    """
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    case MilestoneFilterViewModel.validate(form_params) do
      {:ok, filter_options, _changeset} ->
        path = build_filter_path(socket.assigns.current_team, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  defp build_path_fn(team, filter_options) do
    fn
      :reset -> build_filter_path(team, %MilestoneFilterViewModel{})
      changed -> build_filter_path(team, Map.merge(filter_options, Map.new(changed)))
    end
  end

  defp build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/teams/#{team}/milestones?#{query_params}"
  end
end
