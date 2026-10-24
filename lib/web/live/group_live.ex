defmodule Web.GroupLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.GroupRule

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
  alias App.Model.GroupRule
  alias App.Operation.AddGroupRule
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo
  alias App.ViewData.GroupRules

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :editing, false)}
  end

  def handle_params(params, _uri, socket) do
    current_team = socket.assigns.current_team
    group = find_group(params["id"], current_team.id)
    members = list_members_for_group(group)

    socket =
      socket
      |> assign(:page_title, group.title)
      |> assign(:group, group)
      |> assign(:members, members)
      |> assign(:recent_changes, GroupMembershipChange.recent_for_group(group))
      |> reload()

    {:noreply, socket}
  end

  def handle_event("edit-rules", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  def handle_event("done-editing", _params, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  # The ids in these events come from the browser, so each one is looked up through the
  # current team and group before anything changes. A group that would make a loop is
  # refused.
  def handle_event("add-rule", %{"target" => ""}, socket), do: {:noreply, socket}

  def handle_event("add-rule", %{"kind" => kind, "target" => value}, socket) do
    %{group: group, current_team: team} = socket.assigns
    kind = Map.fetch!(%{"in" => :in, "not_in" => :not_in, "standing" => :standing}, kind)
    {:noreply, add_rule(socket, kind, GroupRules.find_target!(team.id, value), group)}
  end

  def handle_event("add-standing-active", _params, socket),
    do: {:noreply, add_rule(socket, :standing, {:standing, :active}, socket.assigns.group)}

  def handle_event("remove-rule", %{"rule-id" => id}, socket) do
    socket.assigns.group |> GroupRule.find!(id) |> GroupRule.delete!()
    {:noreply, reload(socket)}
  end

  defp add_rule(socket, kind, target, group) do
    case AddGroupRule.call(group, kind, target) do
      :ok -> reload(socket)
      {:error, message} -> put_flash(socket, :error, message)
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Groups" path={~p"/teams/#{@current_team}/groups"} />
      <:item label={@group.title} />
    </.breadcrumbs>

    <h1 class="title">{@group.title}</h1>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content group={@group} members={@members} team={@current_team} />
      </aside>
      <main class="content-2/3">
        <h2 class="subheading">Group rules</h2>
        <.rule_summary
          :if={!@editing}
          rules={@named_rules}
          referenced={@referenced}
          team={@current_team}
        />
        <.rule_editor
          :if={@editing}
          rows={@editor_rows}
          options={@options}
          new_path={~p"/teams/#{@current_team}/endorsements/new?group_id=#{@group.id}"}
          add_confirm={@rules == [] && @flip_warning[:first_rule]}
          suggest_standing={GroupRules.suggest_standing?(@rules)}
        />
        <.rule_preview
          :if={@rules != []}
          preview={@preview}
          team={@current_team}
          group={@group}
        />
        <.recent_changes changes={@recent_changes} team={@current_team} />
        <.main_content members={@members} team={@current_team} />
      </main>
    </div>
    """
  end

  defp sidebar_content(assigns) do
    ~H"""
    <dl>
      <dt>Actions</dt>
      <dd>
        <ul id="group-actions" class="action-list">
          <li :if={D4H.records?(@team)}>
            <.a id="group-edit" navigate={~p"/teams/#{@team}/groups/#{@group.id}/edit"}>Rename or delete</.a>
          </li>
          <li :if={!D4H.records?(@team)}>
            <.a external={true} href={D4H.build_url(@team, "/team/members")}>Open {D4H.service_name(
              @team
            )} members</.a>
          </li>
        </ul>
      </dd>
      <dt>Members</dt>
      <dd>{length(@members)}</dd>
    </dl>
    """
  end

  defp rule_summary(assigns) do
    ~H"""
    <div class="card flex items-center justify-between gap-4">
      <div>
        <p id="rule-sentence" class="mb-0">{rule_sentence(@rules)}</p>
        <p
          :for={ref <- @referenced}
          id={"rule-group-#{ref_id(ref)}"}
          class="hint mb-0"
        >
          <.referenced_group ref={ref} team={@team} />
        </p>
      </div>
      <.button id="edit-rules" class="shrink-0" phx-click="edit-rules">
        {if @rules == [], do: "Add rules", else: "Edit rules"}
      </.button>
    </div>
    """
  end

  defp referenced_group(%{ref: {:missing, g}} = assigns) do
    assigns = assign(assigns, :g, g)

    ~H"""
    <span class="text-danger-text">A group in these rules was deleted ({@g}).</span>
    """
  end

  defp referenced_group(%{ref: {:list, group}} = assigns) do
    assigns = assign(assigns, :group, group)

    ~H"""
    <.a navigate={~p"/teams/#{@team}/groups/#{@group.id}"}>{@group.title}</.a> is a list kept by hand.
    """
  end

  defp referenced_group(%{ref: {:smart, group, rules}} = assigns) do
    assigns = assign(assigns, group: group, rules: rules)

    ~H"""
    <.a navigate={~p"/teams/#{@team}/groups/#{@group.id}"}>{@group.title}</.a>: {rule_sentence(@rules)}
    """
  end

  defp ref_id({:missing, g}), do: "missing-#{g}"
  defp ref_id({:list, group}), do: group.id
  defp ref_id({:smart, group, _rules}), do: group.id

  defp rule_preview(assigns) do
    ~H"""
    <div class="mt-4">
      <h2 class="subheading">Rule preview</h2>
      <div :if={@preview.problems != []} id="rule-broken" class="callout text-sm">
        <p>These rules plan no changes until they're fixed.</p>
        <ul>
          <li :for={problem <- @preview.problems}>
            {BuildGroupRulePreview.describe_problem(problem)}
          </li>
        </ul>
      </div>
      <p :if={@preview.problems == []} class="hint mb-2">
        What these rules would change in the group.
      </p>

      <.change_list
        id="would-remove"
        title="Would be removed"
        title_class="text-danger-text"
        rows={@preview.to_remove}
        team={@team}
      />
      <.change_list
        id="would-add"
        title="Would be added"
        title_class="text-success-text"
        rows={@preview.to_add}
        team={@team}
      />
      <.change_list
        id="expiring"
        title={"Expiring within #{Service.Format.days(BuildGroupRulePreview.expiring_days())}"}
        title_class=""
        rows={@preview.expiring}
        team={@team}
      />

      <p
        :if={@preview.problems == [] && @preview.to_add == [] && @preview.to_remove == []}
        class="hint"
      >
        No changes. The group matches its rules.
      </p>

      <.button
        :if={@preview.to_add != [] || @preview.to_remove != []}
        id="review-changes"
        variant={:primary}
        navigate={~p"/teams/#{@team}/groups/#{@group.id}/review"}
      >
        Review changes
      </.button>
    </div>
    """
  end

  defp recent_changes(assigns) do
    ~H"""
    <div :if={@changes != []} class="mt-4">
      <h2 class="subheading">Recent changes</h2>
      <.table id="recent-changes" rows={@changes} class="table-striped">
        <:col :let={change} label="When" class="w-px whitespace-nowrap">
          {Service.Format.datetime_short(change.inserted_at, @team.timezone)}
        </:col>
        <:col :let={change} label="Change">
          <span class={change.error && "text-danger-text"}>{change_verb(change)}</span>
          <.a navigate={~p"/teams/#{@team}/members/#{change.member.id}/qualifications"}>{change.member.name}</.a>
          · {change.reason}
          <span :if={change.user}>· by {change.user.email}</span>
          <div :if={change.error} class="text-sm text-danger-text">{change.error}</div>
        </:col>
      </.table>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :title_class, :string, required: true
  attr :rows, :list, required: true
  attr :team, :map, required: true

  defp change_list(assigns) do
    ~H"""
    <div :if={@rows != []} class="mb-4">
      <h3 class={["font-semibold mb-2", @title_class]}>{@title} ({length(@rows)})</h3>
      <.table id={@id} rows={@rows} row_id={&"#{@id}-#{&1.member.id}"} class="table-striped">
        <:col :let={row} label="Member" class="md:w-1/3">
          <.a navigate={~p"/teams/#{@team}/members/#{row.member.id}/qualifications"}>{row.member.name}</.a>
        </:col>
        <:col :let={row} label="Why">
          {row.reason}
          <.badge :if={row[:days]} kind={:warning}>
            {Service.Format.days(row.days)}
          </.badge>
        </:col>
      </.table>
    </div>
    """
  end

  defp main_content(assigns) do
    ~H"""
    <h2 class="subheading mt-4">Members ({length(@members)})</h2>
    <.table
      :if={@members != []}
      id="group_members"
      rows={@members}
      class="table-striped"
    >
      <:col :let={gm} label="Member">
        <.a navigate={~p"/teams/#{@team}/members/#{gm.member.id}"}>{gm.member.name}</.a>
      </:col>
    </.table>
    <p :if={@members == []} class="text-text-muted">No members in this group.</p>
    """
  end

  defp change_verb(%{action: :add, error: nil}), do: "Added"
  defp change_verb(%{action: :remove, error: nil}), do: "Removed"
  defp change_verb(%{action: :add}), do: "Could not add"
  defp change_verb(%{action: :remove}), do: "Could not remove"

  defp reload(socket) do
    %{group: group, current_team: team} = socket.assigns
    context = BuildGroupRulePreview.load(team)
    rules = Map.get(context.rules, group.d4h_group_id, [])

    flip_warning = flip_warnings(context, group)

    socket
    |> assign(:context, context)
    |> assign(:rules, rules)
    |> assign(:flip_warning, flip_warning)
    |> assign(:named_rules, Enum.map(rules, &GroupRules.named(&1, context)))
    |> assign(:referenced, GroupRules.referenced_groups(rules, context))
    |> assign(:editor_rows, editor_rows(rules, context, team, group, flip_warning))
    |> assign(:options, rule_options(context, group, rules))
    |> assign(:preview, BuildGroupRulePreview.preview(context, team, group))
  end

  defp flip_warnings(context, group) do
    for change <- [:first_rule, :last_rule],
        warning = GroupRules.flip_warning(context, group.d4h_group_id, change),
        into: %{},
        do: {change, warning}
  end

  # The add menu: groups and endorsements, then the standings no Standing rule has yet.
  defp rule_options(context, group, rules) do
    standings = {"Standing", rules |> standing_taken() |> GroupRules.standing_options()}

    context
    |> GroupRules.options(group.d4h_group_id)
    |> Enum.concat([standings])
    |> Enum.reject(&(elem(&1, 1) == []))
  end

  defp standing_taken(rules),
    do: for(%{kind: :standing, targets: targets} <- rules, target <- targets, do: target)

  # The editor's rows as plain maps, so the style guide can render it too. Removing the
  # last rule warns when other groups' rules name this one.
  defp editor_rows(rules, context, team, group, flip_warning) do
    for rule <- rules do
      %{
        id: rule.id,
        kind: rule.kind,
        names: Enum.map_join(rule.targets, " or ", &GroupRules.name(&1, context)),
        path: ~p"/teams/#{team}/groups/#{group.id}/rules/#{rule.id}",
        confirm: if(length(rules) == 1, do: flip_warning[:last_rule])
      }
    end
  end

  defp find_group(id, team_id) do
    Group
    |> where([g], g.id == ^id and g.team_id == ^team_id)
    |> Repo.one!()
  end

  defp list_members_for_group(group) do
    GroupMember
    |> where([gm], gm.group_id == ^group.id)
    |> join(:inner, [gm], m in assoc(gm, :member))
    |> order_by([gm, m], asc: m.name)
    |> preload([gm, m], member: m)
    |> Repo.all()
  end
end
