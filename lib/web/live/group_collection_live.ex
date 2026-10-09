defmodule Web.GroupCollectionLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRuleClause
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Groups")}
  end

  def handle_params(_params, _uri, socket) do
    current_team = socket.assigns.current_team
    groups = list_groups_with_counts(current_team)

    socket =
      socket
      |> assign(:groups, groups)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team} />
    <div class="heading-row">
      <h1 class="title">{@page_title}</h1>
      <.button
        :if={D4H.records?(@current_team)}
        id="group-add"
        navigate={~p"/teams/#{@current_team}/groups/new"}
      >
        Add group
      </.button>
    </div>

    <div :if={@groups != []} class="table-summary">
      <span class="table-summary-count">
        {Service.Format.count(length(@groups), one: "%d group", many: "%d groups")}
      </span>
    </div>

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

    <.empty_state :if={@groups == []} id="no-groups" title="No groups yet">
      SAR Duty copies groups from D4H when it refreshes.
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
      GroupRuleClause
      |> where([c], c.team_id == ^team.id)
      |> distinct(true)
      |> select([c], c.d4h_group_id)
      |> Repo.all()
      |> MapSet.new()

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
          do: pending_changes(team, row.group)

      Map.put(row, :rules, rules)
    end)
  end

  # :broken, or how many adds and removes the rules would make now.
  defp pending_changes(team, group) do
    preview = BuildGroupRulePreview.for_group(team, group)

    if preview.missing_qualification_ids == [],
      do: length(preview.to_add) + length(preview.to_remove),
      else: :broken
  end
end
