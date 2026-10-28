defmodule Web.GroupLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.GroupRule
  import Web.Components.Standing, only: [standing_badge: 1]

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
  alias App.Model.GroupRule
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.AddGroupRule
  alias App.Operation.BuildGroupRulePreview
  alias App.Operation.SetGroupMember
  alias App.Repo
  alias App.ViewData.GroupMemberFacts
  alias App.ViewData.GroupRules

  def mount(_params, _session, socket) do
    {:ok, assign(socket, editing: false, rule_kind: :in)}
  end

  def handle_params(params, _uri, socket) do
    current_team = socket.assigns.current_team
    group = find_group(params["id"], current_team.id)

    socket =
      socket
      |> assign(:page_title, group.title)
      |> assign(:group, group)
      |> assign(:organization_name, Team.organization_name(current_team))
      |> load_members()
      |> reload()

    {:noreply, socket}
  end

  defp load_members(socket) do
    %{group: group, current_team: team} = socket.assigns
    members = list_members_for_group(group)
    now = DateTime.utc_now()

    socket
    |> assign(:members, members)
    |> assign(:facts, GroupMemberFacts.load(team, Enum.map(members, & &1.member), now))
    |> assign(:other_members, other_members(team, members, now))
    |> assign(:recent_changes, GroupMembershipChange.recent_for_group(group))
  end

  # A group without rules is a list kept by hand. The ids come from the browser, so each
  # is looked up in the lists this page loaded through the current team. No flash: the
  # table and Recent changes show it.
  def handle_event("add-member", %{"member_id" => id}, socket) do
    %{current_team: team, current_user: user, group: group} = socket.assigns

    case Enum.find(socket.assigns.other_members, &(Integer.to_string(&1.id) == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a member.")}

      member ->
        case SetGroupMember.add(team, member, group, user, DateTime.utc_now()) do
          :ok -> {:noreply, socket |> clear_flash() |> load_members()}
          {:error, text} -> {:noreply, socket |> load_members() |> put_flash(:error, text)}
        end
    end
  end

  def handle_event("remove-member", %{"id" => id}, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case Enum.find(socket.assigns.members, &(Integer.to_string(&1.id) == id)) do
      # Gone already, say from another tab.
      nil ->
        {:noreply, load_members(socket)}

      group_member ->
        case SetGroupMember.remove(team, group_member, user, DateTime.utc_now()) do
          :ok -> {:noreply, socket |> clear_flash() |> load_members()}
          {:error, text} -> {:noreply, socket |> load_members() |> put_flash(:error, text)}
        end
    end
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
    target = GroupRules.find_target!(team.id, value)
    {:noreply, add_rule(socket, rule_kind(kind), target, group)}
  end

  # The second menu follows the first: groups and endorsements, or standings.
  def handle_event("rule-kind", %{"kind" => kind}, socket),
    do: {:noreply, socket |> assign(:rule_kind, rule_kind(kind)) |> assign_options()}

  def handle_event("add-standing-active", _params, socket),
    do: {:noreply, add_rule(socket, :standing, {:standing, :active}, socket.assigns.group)}

  def handle_event("remove-rule", %{"rule-id" => id}, socket) do
    socket.assigns.group |> GroupRule.find!(id) |> GroupRule.delete!()
    {:noreply, reload(socket)}
  end

  defp rule_kind(kind),
    do: Map.fetch!(%{"in" => :in, "not_in" => :not_in, "standing" => :standing}, kind)

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
        <.sidebar_content
          group={@group}
          members={@members}
          team={@current_team}
          organization_name={@organization_name}
        />
      </aside>
      <main class="content-2/3">
        <h2 class="subheading">Group rules</h2>
        <p :if={retiring_group?(@current_team, @group)} id="retiring-group" class="card">
          Members of this group are retiring. It cannot have group rules.
        </p>
        <.rule_summary
          :if={!@editing and !retiring_group?(@current_team, @group)}
          rules={@named_rules}
          referenced={@referenced}
          team={@current_team}
        />
        <.rule_editor
          :if={@editing}
          rows={@editor_rows}
          options={@options}
          kind={@rule_kind}
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
        <.main_content
          members={@members}
          facts={@facts}
          other_members={@other_members}
          ruled?={@rules != []}
          used_by={@used_by}
          group={@group}
          team={@current_team}
        />
        <.recent_changes changes={@recent_changes} team={@current_team} />
      </main>
    </div>
    """
  end

  defp other_members(team, members, now) do
    in_group = MapSet.new(members, & &1.member_id)

    Member
    |> Member.scope(team_id: team.id)
    |> Member.current_query(now)
    |> order_by([m], asc: m.name)
    |> Repo.all()
    |> Enum.reject(&(&1.id in in_group))
  end

  # Everyone in the Retiring group is retiring because they are in it; the badge says nothing.
  defp shown_standing(:retiring, team, group) do
    if retiring_group?(team, group), do: :active, else: :retiring
  end

  defp shown_standing(standing, _team, _group), do: standing

  defp retired_count(facts), do: Enum.count(facts.standing, &(elem(&1, 1) == :retired))

  defp last_attended(nil, _team), do: "Never"
  defp last_attended(started_at, team), do: Service.Format.date_short(started_at, team.timezone)

  # The team's Retiring group (#514) can't have rules: "Standing is Active" on it would
  # take out every member. Settings offer only groups without rules for it.
  defp retiring_group?(team, group), do: team.retiring_d4h_group_id == group.d4h_group_id

  defp sidebar_content(assigns) do
    ~H"""
    <dl>
      <dt>Actions</dt>
      <dd>
        <ul id="group-actions" class="action-list">
          <li :if={!@group.organization_owned}>
            <.a id="group-edit" navigate={~p"/teams/#{@team}/groups/#{@group.id}/edit"}>Rename or delete</.a>
          </li>
          <li :if={!D4H.records?(@team)}>
            <.a external={true} href={D4H.build_url(@team, "/team/members")}>Open {D4H.service_name(
              @team
            )} members</.a>
          </li>
        </ul>
      </dd>
      <%= if @group.organization_owned do %>
        <dt>Belongs to</dt>
        <dd id="group-organization">
          {@organization_name || "Your organization"}
          <span class="hint block">
            Only {@organization_name || "your organization"} can rename or delete it.
          </span>
        </dd>
      <% end %>
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
          <.a navigate={~p"/teams/#{@team}/members/#{change.member.id}"}>{change.member.name}</.a>
          <span :if={change.reason}>· {change.reason}</span>
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
    <p :if={retired_count(@facts) > 0} id="members-retired" class="hint">
      {Service.Format.count(length(@members) - retired_count(@facts),
        one: "%d not retired",
        many: "%d not retired"
      )} · {Service.Format.count(retired_count(@facts), one: "%d retired", many: "%d retired")}
    </p>
    <p :if={@ruled?} id="members-by-rules" class="hint">Its rules decide who is in it.</p>
    <p :if={!@ruled? and @used_by != []} id="used-by" class="hint">
      The rules of <.used_by_links groups={@used_by} team={@team} /> use this group.
    </p>
    <form
      :if={!@ruled? and @other_members != []}
      id="add-member-form"
      phx-submit="add-member"
      class="flex flex-wrap items-center gap-2 mb-4"
    >
      <.combobox
        id="add-member-id"
        name="member_id"
        value=""
        options={Enum.map(@other_members, &{&1.name, &1.id})}
        aria-label="Member"
      />
      <.button id="add-member" phx-disable-with="Adding…">Add to group</.button>
    </form>
    <.table
      :if={@members != []}
      id="group_members"
      rows={@members}
      row_id={&"group-member-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={gm} label="Member">
        <.a navigate={~p"/teams/#{@team}/members/#{gm.member.id}"}>{gm.member.name}</.a>
        <.standing_badge
          id={"group-member-standing-#{gm.member.id}"}
          standing={shown_standing(@facts.standing[gm.member.id], @team, @group)}
        />
      </:col>
      <:col :let={gm} label="Role">{gm.member.position}</:col>
      <:col :let={gm} label="Last attended" class="whitespace-nowrap">
        <span id={"group-member-attended-#{gm.member.id}"}>
          {last_attended(@facts.last_attended[gm.member.id], @team)}
        </span>
      </:col>
      <:col :let={gm} :if={!@ruled?} label="" align="right">
        <.button
          id={"remove-member-#{gm.id}"}
          size={:sm}
          phx-click="remove-member"
          phx-disable-with="Removing…"
          phx-value-id={gm.id}
          data-confirm={"Remove #{gm.member.name} from #{@group.title}?"}
        >
          Remove
        </.button>
      </:col>
    </.table>
    <p :if={@members == []} id="no-members" class="text-text-muted">
      {if @ruled?, do: "Nobody is in this group.", else: "Nobody is in this group. Add a member."}
    </p>
    """
  end

  # "Callout", "Callout and MIT Callout", or "A, B, and C", each a link.
  defp used_by_links(assigns) do
    count = length(assigns.groups)

    assigns =
      assign(assigns, :items, Enum.with_index(assigns.groups, &{&1, separator(&2, count)}))

    ~H"""
    <%= for {group, separator} <- @items do %>
      {separator}<.a navigate={~p"/teams/#{@team}/groups/#{group.id}"}>{group.title}</.a>
    <% end %>
    """
  end

  defp separator(0, _count), do: ""
  defp separator(1, 2), do: " and "
  defp separator(i, count) when i == count - 1, do: ", and "
  defp separator(_i, _count), do: ", "

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
    |> assign(:used_by, used_by(context, group))
    |> assign(:flip_warning, flip_warning)
    |> assign(:named_rules, Enum.map(rules, &GroupRules.named(&1, context)))
    |> assign(:referenced, GroupRules.referenced_groups(rules, context))
    |> assign(:editor_rows, editor_rows(rules, context, team, group, flip_warning))
    |> assign(:preview, BuildGroupRulePreview.preview(context, team, group))
    |> assign_options()
  end

  defp assign_options(socket) do
    %{context: context, current_team: team, group: group, rule_kind: kind} = socket.assigns
    assign(socket, :options, rule_options(kind, context, team, group))
  end

  # The groups whose rules name this one.
  defp used_by(context, group) do
    context.rules
    |> GroupRule.used_by(group.d4h_group_id)
    |> Enum.map(&context.groups[&1])
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.title)
  end

  defp flip_warnings(context, group) do
    for change <- [:first_rule, :last_rule],
        warning = GroupRules.flip_warning(context, group.d4h_group_id, change),
        into: %{},
        do: {change, warning}
  end

  # The add menu for the kind picked: the standings no Standing rule has yet, or groups
  # and endorsements.
  defp rule_options(:standing, context, team, group) do
    rules = Map.get(context.rules, group.d4h_group_id, [])
    rules |> standing_taken() |> GroupRules.standing_options(Team.retiring?(team))
  end

  defp rule_options(_kind, context, _team, group),
    do: GroupRules.options(context, group.d4h_group_id)

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
