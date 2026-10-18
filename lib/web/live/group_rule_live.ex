defmodule Web.GroupRuleLive do
  use Web, :live_view_app_layout

  import Web.Components.GroupRule, only: [kind_label: 1]

  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Model.GroupRuleReference
  alias App.Operation.BuildGroupRulePreview
  alias App.ViewData.GroupRules

  # One rule of a group (#334): its groups and endorsements, or a Standing rule's
  # standings (#366), each with Remove, and a menu to add another, the way an
  # endorsement's page lists its qualifications.
  def handle_params(params, _uri, socket) do
    group = Group.find!(socket.assigns.current_team, params["id"])
    rule = GroupRule.find!(group, params["rule_id"])
    {:noreply, socket |> assign(group: group, rule: rule) |> load()}
  end

  # The ids come from the browser, so each is looked up through the team and the rule. A
  # group that would make a loop is refused.
  def handle_event("add", %{"target" => ""}, socket), do: {:noreply, socket}

  def handle_event("add", %{"target" => value}, socket) do
    %{rule: rule, group: group, context: context, current_team: team} = socket.assigns

    case {rule.kind, GroupRules.find_target!(team.id, value)} do
      {:standing, {:standing, standing}} ->
        GroupRuleReference.add!(rule, standing)

      {_kind, {:standing, _standing}} ->
        nil

      {:standing, _target} ->
        nil

      {_kind, %Group{d4h_group_id: other} = target} ->
        if GroupRule.can_name?(context.rules, group.d4h_group_id, other),
          do: GroupRuleReference.add!(rule, target)

      {_kind, endorsement} ->
        GroupRuleReference.add!(rule, endorsement)
    end

    {:noreply, reload(socket)}
  end

  # Removing the last one removes the rule, and goes back to the group.
  def handle_event("remove", %{"id" => id}, socket) do
    %{rule: rule, group: group, current_team: team} = socket.assigns
    GroupRuleReference.remove!(rule, id)

    if Enum.map(rule.references, &to_string(&1.id)) == [to_string(id)] do
      {:noreply,
       socket
       |> put_flash(:info, "Rule removed.")
       |> push_navigate(to: ~p"/teams/#{team}/groups/#{group.id}")}
    else
      {:noreply, reload(socket)}
    end
  end

  defp reload(socket),
    do:
      socket
      |> assign(:rule, GroupRule.find!(socket.assigns.group, socket.assigns.rule.id))
      |> load()

  defp load(socket) do
    %{group: group, rule: rule, current_team: team} = socket.assigns
    context = BuildGroupRulePreview.load(team)
    targets = GroupRule.targets(rule)
    rules = Map.get(context.rules, group.d4h_group_id, [])

    assign(socket,
      page_title:
        if(rule.kind == :standing, do: "Standing rule", else: "#{kind_label(rule.kind)} rule"),
      context: context,
      rows: Enum.map(rule.references, &row(&1, context, team)),
      options:
        if(rule.kind == :standing,
          do: GroupRules.standing_options(targets),
          else: GroupRules.options(context, group.d4h_group_id, targets)
        ),
      last_confirm:
        if(length(rules) == 1,
          do: GroupRules.flip_warning(context, group.d4h_group_id, :last_rule)
        )
    )
  end

  defp row(reference, context, team) do
    target = GroupRuleReference.target(reference)

    path =
      case target do
        {:group, g} -> (group = context.groups[g]) && ~p"/teams/#{team}/groups/#{group.id}"
        {:endorsement, id} -> ~p"/teams/#{team}/endorsements/#{id}"
        {:standing, _standing} -> nil
      end

    %{
      id: reference.id,
      name: GroupRules.name(target, context),
      kind: target_kind(target),
      path: path,
      missing?: match?({:group, _}, target) and is_nil(path)
    }
  end

  defp target_kind({:group, _g}), do: "Group"
  defp target_kind({:endorsement, _id}), do: "Endorsement"
  defp target_kind({:standing, _standing}), do: "Standing"

  defp meaning(%{kind: :in}, group),
    do:
      "Members of #{group.title} must be in at least one of these groups or hold at least one of these endorsements."

  defp meaning(%{kind: :not_in}, group),
    do:
      "Members of #{group.title} must be in none of these groups and hold none of these endorsements."

  defp meaning(%{kind: :standing}, group),
    do: "Members of #{group.title} must have one of these standings today."

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Groups" path={~p"/teams/#{@current_team}/groups"} />
      <:item label={@group.title} path={~p"/teams/#{@current_team}/groups/#{@group.id}"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <div class="measure">
      <p class="lead" id="rule-meaning">
        {meaning(@rule, @group)}
      </p>

      <.table id="references" rows={@rows} row_id={&"reference-#{&1.id}"}>
        <:col
          :let={row}
          label={if @rule.kind == :standing, do: "Standing", else: "Group or endorsement"}
        >
          <.a :if={row.path} navigate={row.path}>{row.name}</.a>
          <span :if={row.missing?} class="text-danger-text">{row.name}</span>
          <span :if={!row.path and !row.missing?}>{row.name}</span>
        </:col>
        <:col :let={row} label="Kind" class="w-px whitespace-nowrap">{row.kind}</:col>
        <:col :let={row} label="" align="right">
          <.button
            id={"remove-reference-#{row.id}"}
            size={:sm}
            phx-click="remove"
            phx-value-id={row.id}
            data-confirm={length(@rows) == 1 && @last_confirm}
          >
            Remove
          </.button>
        </:col>
      </.table>

      <form :if={@options != []} id="add-reference-form" phx-submit="add" class="mt-4">
        <.input
          type="combobox"
          name="target"
          id="target"
          label={if @rule.kind == :standing, do: "Add a standing", else: "Add a group or endorsement"}
          value=""
          prompt={
            if @rule.kind == :standing,
              do: "Select a standing",
              else: "Select a group or endorsement"
          }
          options={@options}
        />
        <.button>Add to rule</.button>
      </form>
    </div>
    """
  end
end
