defmodule Web.MilestoneCollectionLive do
  @moduledoc """
  The team's milestones (#389): who reached what, newest first. Opens on the last 90 days,
  for thanking people at a meeting or in a newsletter. A member's sidebar links here
  filtered to them, over all time. Members open it too (#440): it comes from attendance
  they see already.
  """

  use Web, {:live_view_app_layout, access: :team, member_events: ["change"]}

  import Web.Components.FilterBar
  import Web.Components.StatSwitch

  alias App.ViewData.MemberMilestones
  alias App.ViewModel.MilestoneFilterViewModel
  alias Service.Format
  alias Web.Components.MilestoneList

  # Worked out once, when the page connects, rather than for the first render too; the
  # filters only pick from them. Until then the page shows its filters and nothing else.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()
    loaded? = connected?(socket)

    {:ok,
     assign(socket,
       page_title: "Milestones",
       now: now,
       loaded?: loaded?,
       milestones: if(loaded?, do: MemberMilestones.for_team(team, now), else: [])
     )}
  end

  def handle_params(params, _uri, socket) do
    case MilestoneFilterViewModel.validate(params) do
      {:ok, filter_options, changeset} ->
        %{current_team: team, milestones: milestones, now: now} = socket.assigns

        any_kind =
          MilestoneFilterViewModel.filter(
            milestones,
            %{filter_options | kind: nil},
            team.timezone,
            now
          )

        shown = MilestoneFilterViewModel.filter(any_kind, filter_options, team.timezone, now)

        {:noreply,
         assign(socket,
           filter_options: filter_options,
           kind_counts: kind_counts(any_kind),
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

    <.stat_switch :if={@loaded?} id="milestone-switch" label="Kind">
      <:view
        :for={{label, kind} <- MilestoneFilterViewModel.kinds()}
        id={"milestone-view-#{if kind == "", do: "all", else: kind}"}
        patch={@path_fn.(kind: if(kind == "", do: nil, else: kind), page: nil)}
        current={(@filter_options.kind || "") == kind}
        count={Map.get(@kind_counts, kind, 0)}
        icon={kind != "" && MilestoneList.icon_name(String.to_existing_atom(kind), :micro)}
      >
        {label}
      </:view>
    </.stat_switch>

    <.filter_bar
      for={@form}
      id="milestone_filter_form"
      count={Format.count(@paginated.total_entries, one: "%d milestone", many: "%d milestones")}
      repeats={@paginated.total_entries == Map.get(@kind_counts, @filter_options.kind || "", 0)}
      clear={@path_fn.(:reset)}
      path_fn={@path_fn}
      page={@paginated}
      hidden={[@form[:kind]]}
    >
      <:filter
        field={@form[:member]}
        label="Member"
        type="combobox"
        options={MilestoneFilterViewModel.member_kinds(@milestones)}
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
        <.a navigate={~p"/teams/#{@current_team}/members/#{milestone.member.id}"}>{milestone.member.name}</.a>
      </:col>
      <%!-- The kind's icon, as on its count; not on a phone, where the column would overflow. --%>
      <:col :let={milestone} label="Milestone" class="whitespace-nowrap">
        <span class="icon-label">
          <.icon
            name={MilestoneList.icon_name(milestone.kind, :micro)}
            class="text-text-muted max-md:hidden"
          />
          {MilestoneList.title(milestone)}
        </span>
      </:col>
      <%!-- Plain text: which activity tipped a total over a line is chance (/styles). --%>
      <:col :let={milestone} label="Activity" class="max-md:hidden">
        {milestone.activity && milestone.activity.title}
      </:col>
    </.table>
    <.pagination class="my-4" paginated={@paginated} path_fn={@path_fn} />

    <.empty_state
      :if={@loaded? and @paginated.entries == []}
      id="no-milestones"
      title="No milestones match"
    >
      Change the filters, or select All under Period.
    </.empty_state>
    """
  end

  # Each kind's milestones, and All's, keyed by the kind filter's values.
  defp kind_counts(milestones) do
    milestones
    |> Enum.frequencies_by(&Atom.to_string(&1.kind))
    |> Map.put("", length(milestones))
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
