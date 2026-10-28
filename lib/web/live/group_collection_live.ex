defmodule Web.GroupCollectionLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  import Web.Components.FilterBar
  import Web.Components.StatSwitch

  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRule
  alias App.Model.Team
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo
  alias Service.StringHelpers

  @views ["all", "organization", "team", "out-of-step"]

  def mount(_params, _session, socket) do
    # The organization's groups name it, so an admin can tell where one came from.
    organization_name = Team.organization_name(socket.assigns.current_team)

    {:ok,
     assign(socket,
       page_title: "Groups",
       organization_name: organization_name || "Your organization",
       has_organization?: organization_name != nil
     )}
  end

  # `?view=organization` and `team` split the list by owner (#652), shown only when the
  # team has an organization that owns some. `out-of-step` is the groups whose rules
  # would add or remove members now, or need fixing.
  def handle_params(params, _uri, socket) do
    view = params["view"] || "all"
    unless view in @views, do: raise(Web.Status.NotFound)

    groups = list_groups_with_counts(socket.assigns.current_team)
    q = String.trim(params["q"] || "")
    in_view = in_view(view, groups)

    socket =
      socket
      |> assign_counts(groups)
      |> assign(
        view: view,
        q: q,
        form: to_form(%{"q" => q}, as: "form"),
        groups: Enum.filter(in_view, &StringHelpers.matches?(&1.group.title, q)),
        in_view_count: length(in_view)
      )

    {:noreply, socket}
  end

  defp assign_counts(socket, groups) do
    owned = Enum.filter(groups, & &1.group.organization_owned)

    assign(socket,
      all_count: length(groups),
      organization_count: length(owned),
      team_count: length(groups) - length(owned),
      out_of_step_count: Enum.count(groups, &out_of_step?/1),
      split?: socket.assigns.has_organization? and owned != []
    )
  end

  defp in_view("organization", groups), do: Enum.filter(groups, & &1.group.organization_owned)
  defp in_view("team", groups), do: Enum.reject(groups, & &1.group.organization_owned)
  defp in_view("out-of-step", groups), do: Enum.filter(groups, &out_of_step?/1)
  defp in_view("all", groups), do: groups

  defp out_of_step?(%{rules: rules}), do: rules == :broken or (is_integer(rules) and rules > 0)

  def handle_event("change", %{"form" => %{"q" => q}}, socket) do
    path = groups_path(socket.assigns.current_team, socket.assigns.view, q)
    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  defp groups_path(team, view, q) do
    params =
      Enum.reject([view: view, q: q], fn {key, value} ->
        value == "" or {key, value} == {:view, "all"}
      end)

    ~p"/teams/#{team}/groups?#{params}"
  end

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">{@page_title}</h1>
      <:action>
        <.button
          id="group-add"
          navigate={~p"/teams/#{@current_team}/groups/new"}
        >
          Add group
        </.button>
      </:action>
    </.heading_row>

    <.stat_switch :if={@all_count > 0} label="Groups">
      <:view
        id="groups-all-link"
        patch={groups_path(@current_team, "all", @q)}
        current={@view == "all"}
        count={@all_count}
      >
        All
      </:view>
      <:view
        :if={@split?}
        id="groups-organization-link"
        patch={groups_path(@current_team, "organization", @q)}
        current={@view == "organization"}
        count={@organization_count}
      >
        {@organization_name}
      </:view>
      <:view
        :if={@split?}
        id="groups-team-link"
        patch={groups_path(@current_team, "team", @q)}
        current={@view == "team"}
        count={@team_count}
      >
        {@current_team.name}
      </:view>
      <:view
        id="groups-out-of-step-link"
        patch={groups_path(@current_team, "out-of-step", @q)}
        current={@view == "out-of-step"}
        count={@out_of_step_count}
      >
        Out of step
      </:view>
    </.stat_switch>

    <.filter_bar
      :if={@all_count > 0}
      for={@form}
      id="group_filter_form"
      count={Service.Format.count(length(@groups), one: "%d group", many: "%d groups")}
      repeats={length(@groups) == @in_view_count}
      clear={groups_path(@current_team, @view, "")}
    >
      <:search field={@form[:q]} />
    </.filter_bar>

    <.table
      :if={@groups != []}
      id="group_collection"
      rows={@groups}
      row_id={&"group-#{&1.group.id}"}
      class="table-striped"
    >
      <:col :let={g} label="Group">
        <.a navigate={~p"/teams/#{@current_team}/groups/#{g.group.id}"}>{g.group.title}</.a>
        <span :if={g.group.organization_owned and @view != "organization"} class="hint">
          · {@organization_name}
        </span>
      </:col>
      <:col :let={g} label="Rules" class="w-px whitespace-nowrap">
        <.rules_status status={g.rules} />
      </:col>
      <:col :let={g} label="Members" class="w-px whitespace-nowrap" align="right">
        {g.member_count}
      </:col>
    </.table>

    <.empty_state :if={@all_count == 0} id="no-groups" title="No groups yet">
      Add one, or refresh to bring in the team's groups.
    </.empty_state>
    <.empty_state
      :if={@all_count > 0 and @groups == [] and @q != ""}
      id="no-matching-groups"
      title="No groups match"
    >
      Change the search.
    </.empty_state>
    <.empty_state
      :if={@groups == [] and @q == "" and @view == "out-of-step"}
      id="no-out-of-step-groups"
      title="Every group is up to date"
    >
      No rules would add or remove anyone now.
    </.empty_state>
    <.empty_state
      :if={@groups == [] and @q == "" and @view == "team"}
      id="no-own-groups"
      title="No groups of its own"
    >
      Each one is {@organization_name}'s.
    </.empty_state>
    """
  end

  defp rules_status(%{status: nil} = assigns), do: ~H""

  defp rules_status(%{status: :broken} = assigns) do
    ~H"""
    <.badge kind={:danger}>Rules need fixing</.badge>
    """
  end

  defp rules_status(%{status: 0} = assigns) do
    ~H"""
    <.badge kind={:success}>Up to date</.badge>
    """
  end

  defp rules_status(assigns) do
    ~H"""
    <.badge kind={:warning}>{@status} pending</.badge>
    """
  end

  defp list_groups_with_counts(team) do
    ruled_group_ids =
      team.id
      |> GroupRule.ruled_d4h_group_ids_query()
      |> Repo.all()
      |> MapSet.new()

    context = BuildGroupRulePreview.load(team)

    Group
    |> where([g], g.team_id == ^team.id)
    |> join(:left, [g], gm in GroupMember, on: gm.group_id == g.id)
    |> group_by([g], g.id)
    |> order_by([g], asc: g.title)
    |> select([g, gm], %{group: g, member_count: count(gm.id)})
    |> Repo.all()
    |> Enum.map(fn row ->
      rules =
        if MapSet.member?(ruled_group_ids, row.group.d4h_group_id),
          do: pending_changes(context, team, row.group)

      Map.put(row, :rules, rules)
    end)
  end

  # :broken, or how many adds and removes the rules would make now.
  defp pending_changes(context, team, group) do
    preview = BuildGroupRulePreview.preview(context, team, group)

    if preview.problems == [],
      do: length(preview.to_add) + length(preview.to_remove),
      else: :broken
  end
end
