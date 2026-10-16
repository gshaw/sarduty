defmodule Web.GroupRuleLive do
  use Web, :live_view_app_layout

  import Web.Components.GroupRule, only: [kind_label: 1]

  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Model.GroupRuleReference
  alias App.Operation.BuildGroupRulePreview
  alias App.ViewData.GroupRules

  # One rule of a group (#334): its groups and endorsements, each with Remove, and a menu
  # to add another, the way an endorsement's page lists its qualifications.
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

    case GroupRules.find_target!(team.id, value) do
      %Group{d4h_group_id: other} = target ->
        if GroupRule.can_name?(context.rules, group.d4h_group_id, other),
          do: GroupRuleReference.add!(rule, target)

      endorsement ->
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
      page_title: "#{kind_label(rule.kind)} rule",
      context: context,
      rows: Enum.map(rule.references, &row(&1, context, team)),
      options: GroupRules.options(context, group.d4h_group_id, targets),
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
      end

    %{
      id: reference.id,
      name: GroupRules.name(target, context),
      kind: if(elem(target, 0) == :group, do: "Group", else: "Endorsement"),
      path: path
    }
  end

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
        {if @rule.kind == :in,
          do:
            "Members of #{@group.title} must be in at least one of these groups or hold at least one of these endorsements.",
          else:
            "Members of #{@group.title} must be in none of these groups and hold none of these endorsements."}
      </p>

      <.table id="references" rows={@rows} row_id={&"reference-#{&1.id}"}>
        <:col :let={row} label="Group or endorsement">
          <.a :if={row.path} navigate={row.path}>{row.name}</.a>
          <span :if={!row.path} class="text-danger-text">{row.name}</span>
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
          type="select"
          name="target"
          id="target"
          label="Add a group or endorsement"
          value=""
          prompt="Select a group or endorsement"
          options={@options}
        />
        <.button>Add to rule</.button>
      </form>
    </div>
    """
  end
end
