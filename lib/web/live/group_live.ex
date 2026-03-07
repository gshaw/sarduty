defmodule Web.GroupLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRuleClause
  alias App.Model.GroupRuleClauseQualification
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
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
    preview = compute_preview(clauses, qualifications, members, current_team.id)

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

  def handle_event("delete-clause", %{"clause-id" => clause_id}, socket) do
    GroupRuleClause.delete!(clause_id)

    {:noreply, reload(socket)}
  end

  def handle_event("add-qualification", %{"clause-id" => clause_id, "qualification-id" => qual_id}, socket) do
    if qual_id != "" do
      GroupRuleClauseQualification.insert!(%{
        group_rule_clause_id: clause_id,
        d4h_qualification_id: find_qualification_d4h_id(socket.assigns.qualifications, qual_id)
      })
    end

    {:noreply, reload(socket)}
  end

  def handle_event("remove-qualification", %{"qualification-id" => qual_id}, socket) do
    GroupRuleClauseQualification.delete!(qual_id)

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
    <h2 class="subtitle mb-p05">Qualification Rules</h2>
    <p :if={@clauses == []} class="text-secondary-1 mb-p">
      No rules defined. Add a clause to define which qualifications members must hold.
    </p>

    <div :for={clause <- @clauses} class="mb-p border rounded p-p">
      <div class="flex justify-between items-center mb-p05">
        <h3 class="font-semibold">Clause — member must hold ANY of:</h3>
        <button
          phx-click="delete-clause"
          phx-value-clause-id={clause.id}
          class="btn btn-sm btn-danger"
          data-confirm="Delete this clause and all its qualifications?"
        >
          Delete clause
        </button>
      </div>

      <div class="flex flex-wrap gap-2 mb-p05">
        <span
          :for={cq <- clause.group_rule_clause_qualifications}
          class="inline-flex items-center gap-1 rounded bg-base-200 px-2 py-1 text-sm"
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
        <select name="qualification-id" class="block rounded border shadow-sm text-sm">
          <option value="">Add qualification...</option>
          {Phoenix.HTML.Form.options_for_select(
            available_qualifications(@qualifications, clause.group_rule_clause_qualifications),
            nil
          )}
        </select>
        <button type="submit" class="btn btn-sm">Add</button>
      </form>
    </div>

    <button phx-click="add-clause" class="btn btn-sm">
      + Add clause
    </button>
    """
  end

  defp rule_preview(assigns) do
    ~H"""
    <div :if={@clauses != []} class="mt-p">
      <h2 class="subtitle mb-p05">Rule Preview</h2>
      <p class="text-secondary-1 text-sm mb-p05">
        Shows what would change if these rules were applied to the group.
      </p>

      <div :if={@preview.to_add != [] || @preview.to_remove != []} class="grid grid-cols-2 gap-p">
        <div :if={@preview.to_add != []}>
          <h3 class="font-semibold text-success-1 mb-p05">Would be added ({length(@preview.to_add)})</h3>
          <ul class="text-sm">
            <li :for={member <- @preview.to_add}>
              <.a navigate={~p"/#{@team.subdomain}/members/#{member.id}"}>{member.name}</.a>
            </li>
          </ul>
        </div>
        <div :if={@preview.to_remove != []}>
          <h3 class="font-semibold text-danger-1 mb-p05">Would be removed ({length(@preview.to_remove)})</h3>
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
    <h2 class="subtitle mb-p05 mt-p">Members ({length(@members)})</h2>
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
    qualifications = socket.assigns.qualifications
    preview = compute_preview(clauses, qualifications, members, team.id)

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

  defp available_qualifications(qualifications, existing_clause_quals) do
    existing_d4h_ids = MapSet.new(existing_clause_quals, & &1.d4h_qualification_id)

    qualifications
    |> Enum.reject(&MapSet.member?(existing_d4h_ids, &1.d4h_qualification_id))
    |> Enum.map(&{&1.title, &1.id})
  end

  defp compute_preview(clauses, qualifications, current_group_members, team_id) do
    if clauses == [] || Enum.any?(clauses, &(&1.group_rule_clause_qualifications == [])) do
      %{to_add: [], to_remove: []}
    else
      qualifying_member_ids = compute_qualifying_members(clauses, qualifications, team_id)
      current_member_ids = MapSet.new(current_group_members, & &1.member.id)

      to_add =
        qualifying_member_ids
        |> MapSet.difference(current_member_ids)
        |> load_members()

      to_remove =
        current_member_ids
        |> MapSet.difference(qualifying_member_ids)
        |> load_members()

      %{to_add: to_add, to_remove: to_remove}
    end
  end

  defp compute_qualifying_members(clauses, qualifications, team_id) do
    # For each clause, find the set of members who hold any qualification in that clause
    # Then intersect all clause sets (CNF: all clauses must pass)
    clause_member_sets =
      Enum.map(clauses, fn clause ->
        d4h_qual_ids =
          Enum.map(clause.group_rule_clause_qualifications, & &1.d4h_qualification_id)

        qual_ids =
          qualifications
          |> Enum.filter(&(&1.d4h_qualification_id in d4h_qual_ids))
          |> Enum.map(& &1.id)

        if qual_ids == [] do
          MapSet.new()
        else
          MemberQualificationAward
          |> where([a], a.qualification_id in ^qual_ids)
          |> where([a], is_nil(a.ends_at) or a.ends_at > ^DateTime.utc_now())
          |> join(:inner, [a], m in assoc(a, :member))
          |> where([a, m], m.team_id == ^team_id)
          |> select([a], a.member_id)
          |> distinct(true)
          |> Repo.all()
          |> MapSet.new()
        end
      end)

    case clause_member_sets do
      [] -> MapSet.new()
      [first | rest] -> Enum.reduce(rest, first, &MapSet.intersection(&2, &1))
    end
  end

  defp load_members(member_ids) do
    ids = MapSet.to_list(member_ids)

    if ids == [] do
      []
    else
      App.Model.Member
      |> where([m], m.id in ^ids)
      |> order_by([m], asc: m.name)
      |> Repo.all()
    end
  end
end
