defmodule Web.GroupLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.GroupRule

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
  alias App.Model.GroupRuleClause
  alias App.Model.GroupRuleClauseQualification
  alias App.Model.Qualification
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :editing, false)}
  end

  def handle_params(params, _uri, socket) do
    current_team = socket.assigns.current_team
    group = find_group(params["id"], current_team.id)
    members = list_members_for_group(group)
    clauses = GroupRuleClause.get_all_for_group(current_team.id, group.d4h_group_id)
    qualifications = Qualification.get_all(current_team.id)
    preview = build_preview(clauses, members, current_team)

    socket =
      socket
      |> assign(:page_title, group.title)
      |> assign(:group, group)
      |> assign(:members, members)
      |> assign(:clauses, clauses)
      |> assign(:qualifications, qualifications)
      |> assign(:preview, preview)
      |> assign(:recent_changes, GroupMembershipChange.recent_for_group(group))

    {:noreply, socket}
  end

  def handle_event("edit-rules", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  def handle_event("done-editing", _params, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("add-clause", _params, socket) do
    group = socket.assigns.group
    team = socket.assigns.current_team

    GroupRuleClause.insert!(%{team_id: team.id, d4h_group_id: group.d4h_group_id})

    {:noreply, reload(socket)}
  end

  # The ids in these events come from the browser, so each one is looked up
  # through the current group before anything changes.
  def handle_event("delete-clause", %{"clause-id" => clause_id}, socket) do
    socket.assigns.group
    |> GroupRuleClause.find!(clause_id)
    |> GroupRuleClause.delete!()

    {:noreply, reload(socket)}
  end

  def handle_event("rename-clause", %{"clause-id" => clause_id, "name" => name}, socket) do
    socket.assigns.group
    |> GroupRuleClause.find!(clause_id)
    |> GroupRuleClause.rename(name)

    {:noreply, reload(socket)}
  end

  def handle_event(
        "add-qualification",
        %{"clause-id" => clause_id, "qualification-id" => qual_id},
        socket
      ) do
    clause = GroupRuleClause.find!(socket.assigns.group, clause_id)

    if qual_id != "" do
      GroupRuleClauseQualification.insert!(%{
        group_rule_clause_id: clause.id,
        d4h_qualification_id: find_qualification_d4h_id(socket.assigns.qualifications, qual_id)
      })
    end

    {:noreply, reload(socket)}
  end

  def handle_event("remove-qualification", %{"qualification-id" => qual_id}, socket) do
    socket.assigns.group
    |> GroupRuleClauseQualification.find!(qual_id)
    |> GroupRuleClauseQualification.delete!()

    {:noreply, reload(socket)}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
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
          clauses={@clauses}
          qualifications={@qualifications}
        />
        <.clause_editor :if={@editing} clauses={editor_clauses(@clauses, @qualifications)} />
        <.rule_preview
          preview={@preview}
          team={@current_team}
          group={@group}
          clauses={@clauses}
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
        <ul class="action-list">
          <li :if={D4H.hosted?(@team)}>
            <.a id="group-edit" navigate={~p"/teams/#{@team}/groups/#{@group.id}/edit"}>
              Change or delete
            </.a>
          </li>
          <li :if={!D4H.hosted?(@team)}>
            <.a external={true} href={D4H.build_url(@team, "/team/members")}>
              Open D4H members
            </.a>
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
      <p id="rule-sentence" class="mb-0">{rule_sentence(@clauses, @qualifications)}</p>
      <.button id="edit-rules" size={:sm} class="shrink-0" phx-click="edit-rules">
        {if @clauses == [], do: "Add rules", else: "Edit rules"}
      </.button>
    </div>
    """
  end

  defp rule_preview(assigns) do
    ~H"""
    <div :if={@clauses != []} class="mt-4">
      <h2 class="subheading">Rule preview</h2>
      <p
        :if={@preview.missing_qualification_ids != []}
        id="rule-broken"
        class="callout text-sm"
      >
        These rules name a qualification that is no longer in D4H. Remove or replace it to
        see the preview.
      </p>
      <p :if={@preview.missing_qualification_ids == []} class="hint mb-2">
        What these rules would change in the D4H group.
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
        title={"Expiring within #{BuildGroupRulePreview.expiring_days()} days"}
        title_class=""
        rows={@preview.expiring}
        team={@team}
      />

      <p
        :if={
          @preview.missing_qualification_ids == [] && @preview.to_add == [] &&
            @preview.to_remove == []
        }
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
          <.a navigate={~p"/teams/#{@team}/members/#{change.member.id}/qualifications"}>
            {change.member.name}
          </.a>
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
          <.a navigate={~p"/teams/#{@team}/members/#{row.member.id}/qualifications"}>
            {row.member.name}
          </.a>
        </:col>
        <:col :let={row} label="Why">
          {row.reason}
          <.badge :if={row[:days]} kind={:warning}>
            {Service.Format.count(row.days, one: "%d day", many: "%d days")}
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
        <.a navigate={~p"/teams/#{@team}/members/#{gm.member.id}"}>
          {gm.member.name}
        </.a>
      </:col>
    </.table>
    <p :if={@members == []} class="text-text-muted">No members in this group.</p>
    """
  end

  defp change_verb(%{action: :add, error: nil}), do: "Added"
  defp change_verb(%{action: :remove, error: nil}), do: "Removed"
  defp change_verb(%{action: :add}), do: "Could not add"
  defp change_verb(%{action: :remove}), do: "Could not remove"

  # The editor's clauses as plain maps, so the style guide can render it too.
  defp editor_clauses(clauses, qualifications) do
    for clause <- clauses do
      %{
        id: clause.id,
        name: clause.name,
        confirm: delete_clause_confirmation(clause),
        qualifications:
          for cq <- clause.group_rule_clause_qualifications do
            %{
              id: cq.id,
              title: qualification_title(qualifications, cq.d4h_qualification_id),
              known?: qualification_known?(qualifications, cq.d4h_qualification_id)
            }
          end,
        options: available_qualifications(qualifications, clause.group_rule_clause_qualifications)
      }
    end
  end

  defp delete_clause_confirmation(clause) do
    name = if clause.name, do: "the #{clause.name} clause", else: "this clause"
    count = length(clause.group_rule_clause_qualifications)

    qualifications =
      Service.Format.count(count, one: "its %d qualification", many: "its %d qualifications")

    "Delete #{name} and #{qualifications}?"
  end

  defp reload(socket) do
    group = socket.assigns.group
    team = socket.assigns.current_team
    members = socket.assigns.members
    clauses = GroupRuleClause.get_all_for_group(team.id, group.d4h_group_id)
    preview = build_preview(clauses, members, team)

    socket
    |> assign(:clauses, clauses)
    |> assign(:preview, preview)
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

  # "Members must hold A and one of B or C", or "First Aid" for a named clause. Titles
  # come from D4H and names from users, so each is escaped before it goes inside
  # <strong>.
  defp rule_sentence([], _qualifications), do: "No rules yet."

  defp rule_sentence(clauses, qualifications) do
    clause_phrases =
      Enum.map(clauses, fn clause ->
        titles =
          Enum.map(clause.group_rule_clause_qualifications, fn cq ->
            strong(qualification_title(qualifications, cq.d4h_qualification_id))
          end)

        case {clause.name, titles} do
          {_name, []} -> "(an empty clause)"
          {nil, [title]} -> title
          {nil, titles} -> ["one of ", join_or(titles)]
          {name, _titles} -> strong(name)
        end
      end)

    Phoenix.HTML.raw(["Members must hold ", Enum.intersperse(clause_phrases, " and "), "."])
  end

  defp strong(text),
    do: [
      "<strong>",
      text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string(),
      "</strong>"
    ]

  defp join_or(titles) do
    {init, [last]} = Enum.split(titles, -1)
    [Enum.intersperse(init, ", "), " or ", last]
  end

  defp qualification_title(qualifications, d4h_qualification_id) do
    case Enum.find(qualifications, &(&1.d4h_qualification_id == d4h_qualification_id)) do
      nil -> "Deleted in D4H (#{d4h_qualification_id})"
      q -> q.title
    end
  end

  defp qualification_known?(qualifications, d4h_qualification_id),
    do: Enum.any?(qualifications, &(&1.d4h_qualification_id == d4h_qualification_id))

  defp find_qualification_d4h_id(qualifications, id) do
    qual = Enum.find(qualifications, &(to_string(&1.id) == to_string(id)))
    qual && qual.d4h_qualification_id
  end

  defp available_qualifications(qualifications, clause_qualifications) do
    existing_d4h_ids = MapSet.new(clause_qualifications, & &1.d4h_qualification_id)

    qualifications
    |> Enum.reject(&MapSet.member?(existing_d4h_ids, &1.d4h_qualification_id))
    |> Enum.map(&{&1.title, &1.id})
  end

  defp build_preview(clauses, members, team) do
    BuildGroupRulePreview.call(clauses, Enum.map(members, & &1.member), team)
  end
end
