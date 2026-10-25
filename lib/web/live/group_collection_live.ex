defmodule Web.GroupCollectionLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  import Web.Components.FilterBar

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRule
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo
  alias Service.StringHelpers

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Groups")}
  end

  def handle_params(params, _uri, socket) do
    groups = list_groups_with_counts(socket.assigns.current_team)
    q = String.trim(params["q"] || "")

    socket =
      assign(socket,
        all_count: length(groups),
        q: q,
        form: to_form(%{"q" => q}, as: "form"),
        groups: Enum.filter(groups, &StringHelpers.matches?(&1.group.title, q))
      )

    {:noreply, socket}
  end

  def handle_event("change", %{"form" => %{"q" => q}}, socket) do
    {:noreply, push_patch(socket, to: groups_path(socket.assigns.current_team, q), replace: true)}
  end

  defp groups_path(team, ""), do: ~p"/teams/#{team}/groups"
  defp groups_path(team, q), do: ~p"/teams/#{team}/groups?#{[q: q]}"

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">{@page_title}</h1>
      <:action>
        <.button
          :if={D4H.records?(@current_team)}
          id="group-add"
          navigate={~p"/teams/#{@current_team}/groups/new"}
        >
          Add group
        </.button>
      </:action>
    </.heading_row>

    <.filter_bar
      :if={@all_count > 0}
      for={@form}
      id="group_filter_form"
      count={Service.Format.count(length(@groups), one: "%d group", many: "%d groups")}
      clear={groups_path(@current_team, "")}
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
      </:col>
      <:col :let={g} label="Rules" class="w-px whitespace-nowrap">
        <.rules_status status={g.rules} />
      </:col>
      <:col :let={g} label="Members" class="w-px whitespace-nowrap" align="right">
        {g.member_count}
      </:col>
    </.table>

    <.empty_state :if={@all_count == 0} id="no-groups" title="No groups yet">
      Groups come in with each refresh.
    </.empty_state>
    <.empty_state
      :if={@all_count > 0 and @groups == []}
      id="no-matching-groups"
      title="No groups match"
    >
      Change the search.
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
