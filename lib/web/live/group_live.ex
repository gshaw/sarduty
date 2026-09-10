defmodule Web.GroupLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRuleClause
  alias App.Model.GroupRuleClauseQualification
  alias App.Model.Qualification
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    current_team = socket.assigns.current_team
    group = find_group(params["id"], current_team.id)
    members = list_members_for_group(group)
    clauses = GroupRuleClause.get_all_for_group(current_team.id, group.d4h_group_id)
    qualifications = Qualification.get_all(current_team.id)
    preview = build_preview(clauses, members, current_team.id)

    socket =
      socket
      |> assign(:page_title, group.title)
      |> assign(:group, group)
      |> assign(:members, members)
      |> assign(:clauses, clauses)
      |> assign(:qualifications, qualifications)
      |> assign(:preview, preview)

    {:noreply, socket}
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
      <:item label="Groups" path={~p"/#{@current_team.subdomain}/groups"} />
      <:item label={@group.title} />
    </.breadcrumbs>

    <h1 class="title">{@group.title}</h1>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content group={@group} members={@members} team={@current_team} />
      </aside>
      <main class="content-2/3">
        <.clause_editor
          clauses={@clauses}
          qualifications={@qualifications}
          team={@current_team}
        />
        <.rule_preview preview={@preview} team={@current_team} clauses={@clauses} />
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
          <li>
            <.a external={true} href={D4H.build_url(@team, "/team/members")}>
              Open D4H Members
            </.a>
          </li>
        </ul>
      </dd>
      <dt>Members</dt>
      <dd>{length(@members)}</dd>
    </dl>
    """
  end

  defp clause_editor(assigns) do
    ~H"""
    <h2 class="subheading mb-p05">Qualification Rules</h2>
    <p class="text-secondary-1 mb-p">
      Define which qualifications members must hold to belong to this group.
      Automatic syncing based on these rules is coming in a future update.
    </p>

    <div :for={clause <- @clauses} class="mb-p border rounded px-p py-p05">
      <div class="flex justify-between items-center mb-p05">
        <h3 class="font-semibold">Clause — member must hold ANY of:</h3>
        <.button
          variant={:danger}
          size={:sm}
          class="ml-p"
          phx-click="delete-clause"
          phx-value-clause-id={clause.id}
          data-confirm="Delete this clause and all its qualifications?"
        >
          Delete clause
        </.button>
      </div>

      <div class="flex flex-wrap gap-2 mb-p05">
        <span
          :for={cq <- clause.group_rule_clause_qualifications}
          class="inline-flex items-center gap-2 rounded bg-base-2 px-2 py-1 text-sm"
        >
          {qualification_title(@qualifications, cq.d4h_qualification_id)}
          <button
            phx-click="remove-qualification"
            phx-value-qualification-id={cq.id}
            class="text-danger-1 hover:text-danger-2 font-bold"
            title="Remove"
          >
            &times;
          </button>
        </span>
        <span
          :if={clause.group_rule_clause_qualifications == []}
          class="text-secondary-1 text-sm italic"
        >
          No qualifications added yet
        </span>
      </div>

      <form phx-submit="add-qualification" class="flex gap-2 items-end">
        <input type="hidden" name="clause-id" value={clause.id} />
        <select
          name="qualification-id"
          class="block rounded border shadow-sm text-sm max-w-xs truncate"
        >
          <option value="">Add qualification...</option>
          {Phoenix.HTML.Form.options_for_select(
            available_qualifications(@qualifications, clause.group_rule_clause_qualifications),
            nil
          )}
        </select>
        <.button size={:sm}>Add</.button>
      </form>
    </div>

    <.button size={:sm} phx-click="add-clause">
      + Add clause
    </.button>
    """
  end

  defp rule_preview(assigns) do
    ~H"""
    <div :if={@clauses != []} class="mt-p">
      <h2 class="subheading mb-p05">Rule Preview</h2>
      <p class="text-secondary-1 text-sm mb-p05">
        Shows what would change if these rules were applied to the group.
      </p>

      <div :if={@preview.to_add != [] || @preview.to_remove != []} class="grid grid-cols-2 gap-p">
        <div :if={@preview.to_add != []}>
          <h3 class="font-semibold text-success-1 mb-p05">
            Would be added ({length(@preview.to_add)})
          </h3>
          <ul class="text-sm">
            <li :for={member <- @preview.to_add}>
              <.a navigate={~p"/#{@team.subdomain}/members/#{member.id}"}>{member.name}</.a>
            </li>
          </ul>
        </div>
        <div :if={@preview.to_remove != []}>
          <h3 class="font-semibold text-danger-1 mb-p05">
            Would be removed ({length(@preview.to_remove)})
          </h3>
          <ul class="text-sm">
            <li :for={member <- @preview.to_remove}>
              <.a navigate={~p"/#{@team.subdomain}/members/#{member.id}"}>{member.name}</.a>
            </li>
          </ul>
        </div>
      </div>

      <p :if={@preview.to_add == [] && @preview.to_remove == []} class="text-secondary-1 text-sm">
        No changes — current group membership matches the rules.
      </p>
    </div>
    """
  end

  defp main_content(assigns) do
    ~H"""
    <h2 class="subheading mb-p05 mt-p">Members ({length(@members)})</h2>
    <.table
      :if={@members != []}
      id="group_members"
      rows={@members}
      class="w-full table-striped"
    >
      <:col :let={gm} label="Member">
        <.a navigate={~p"/#{@team.subdomain}/members/#{gm.member.id}"}>
          {gm.member.name}
        </.a>
      </:col>
    </.table>
    <p :if={@members == []} class="text-secondary-1">No members found.</p>
    """
  end

  defp reload(socket) do
    group = socket.assigns.group
    team = socket.assigns.current_team
    members = socket.assigns.members
    clauses = GroupRuleClause.get_all_for_group(team.id, group.d4h_group_id)
    preview = build_preview(clauses, members, team.id)

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

  defp qualification_title(qualifications, d4h_qualification_id) do
    case Enum.find(qualifications, &(&1.d4h_qualification_id == d4h_qualification_id)) do
      nil -> "Unknown (#{d4h_qualification_id})"
      q -> q.title
    end
  end

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

  defp build_preview(clauses, members, team_id) do
    BuildGroupRulePreview.call(clauses, Enum.map(members, & &1.member.id), team_id)
  end
end
