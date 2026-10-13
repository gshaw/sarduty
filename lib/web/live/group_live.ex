defmodule Web.GroupLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.GroupRule

  alias App.Adapter.D4H
  alias App.Model.Endorsement
  alias App.Model.Group
  alias App.Model.GroupEndorsement
  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
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
    rule = Endorsement.get_all_for_group(group)
    qualifications = Qualification.get_all(current_team.id)
    preview = build_preview(rule, members, current_team)

    socket =
      socket
      |> assign(:page_title, group.title)
      |> assign(:group, group)
      |> assign(:members, members)
      |> assign(:rule, rule)
      |> assign(:qualifications, qualifications)
      |> assign(:endorsements, Endorsement.get_all(current_team.id))
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

  # The ids in these events come from the browser, so each one is looked up through the
  # current team and group before anything changes.
  def handle_event("add-endorsement", %{"endorsement-id" => ""}, socket),
    do: {:noreply, socket}

  def handle_event("add-endorsement", %{"endorsement-id" => id}, socket) do
    endorsement = Endorsement.get!(socket.assigns.current_team.id, id)
    GroupEndorsement.add!(socket.assigns.group, endorsement)
    {:noreply, reload(socket)}
  end

  def handle_event("remove-endorsement", %{"endorsement-id" => id}, socket) do
    endorsement = Endorsement.get!(socket.assigns.current_team.id, id)
    GroupEndorsement.remove!(socket.assigns.group, endorsement.id)
    {:noreply, reload(socket)}
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
          rule={@rule}
          qualifications={@qualifications}
        />
        <.rule_editor
          :if={@editing}
          rows={editor_rows(@rule, @qualifications, @current_team)}
          options={editor_options(@endorsements, @rule)}
          new_path={~p"/teams/#{@current_team}/endorsements/new?group_id=#{@group.id}"}
        />
        <.rule_preview
          preview={@preview}
          team={@current_team}
          group={@group}
          rule={@rule}
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
            <.a id="group-edit" navigate={~p"/teams/#{@team}/groups/#{@group.id}/edit"}>
              Rename or delete
            </.a>
          </li>
          <li :if={!D4H.records?(@team)}>
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
      <p id="rule-sentence" class="mb-0">{rule_sentence(@rule, @qualifications)}</p>
      <.button id="edit-rules" class="shrink-0" phx-click="edit-rules">
        {if @rule == [], do: "Add rules", else: "Edit rules"}
      </.button>
    </div>
    """
  end

  defp rule_preview(assigns) do
    ~H"""
    <div :if={@rule != []} class="mt-4">
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

  # The editor's rows as plain maps, so the style guide can render it too.
  defp editor_rows(endorsements, qualifications, team) do
    for endorsement <- endorsements do
      %{
        id: endorsement.id,
        name: endorsement.name,
        path: ~p"/teams/#{team}/endorsements/#{endorsement.id}",
        qualifications:
          endorsement
          |> Endorsement.qualification_ids()
          |> Enum.map_join(", ", &qualification_title(qualifications, &1))
      }
    end
  end

  defp editor_options(endorsements, in_rule) do
    ids = MapSet.new(in_rule, & &1.id)
    for e <- endorsements, not MapSet.member?(ids, e.id), do: {e.name, e.id}
  end

  defp reload(socket) do
    group = socket.assigns.group
    team = socket.assigns.current_team
    members = socket.assigns.members
    rule = Endorsement.get_all_for_group(group)
    preview = build_preview(rule, members, team)

    socket
    |> assign(:rule, rule)
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

  # "Members must hold GSAR and First Aid." Names come from users, so each is escaped
  # before it goes inside <strong>.
  defp rule_sentence([], _qualifications), do: "No rules yet."

  defp rule_sentence(endorsements, _qualifications) do
    names = Enum.map(endorsements, &strong(&1.name))
    Phoenix.HTML.raw(["Members must hold ", Enum.intersperse(names, " and "), "."])
  end

  defp strong(text),
    do: [
      "<strong>",
      text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string(),
      "</strong>"
    ]

  defp qualification_title(qualifications, d4h_qualification_id) do
    case Enum.find(qualifications, &(&1.d4h_qualification_id == d4h_qualification_id)) do
      nil -> "Deleted in D4H (#{d4h_qualification_id})"
      q -> q.title
    end
  end

  defp build_preview(rule, members, team) do
    BuildGroupRulePreview.call(rule, Enum.map(members, & &1.member), team)
  end
end
