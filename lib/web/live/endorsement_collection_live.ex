defmodule Web.EndorsementCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.Endorsement
  alias App.ViewData.EndorsementRows
  alias App.Worker.PushPassUpdatesWorker
  alias Service.Format

  # Endorsements: a name and the qualifications that earn it. Group rules name them,
  # and a team with ID cards picks which ones its cards list (#320).
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Endorsements") |> assign_rows()}
  end

  def handle_event("save", params, socket) do
    team = socket.assigns.current_team
    known = MapSet.new(socket.assigns.rows, &to_string(&1.id))
    picked = params |> Map.get("ids", []) |> Enum.filter(&MapSet.member?(known, &1))
    Endorsement.set_on_card!(team.id, picked)
    # Passes already on phones change too; the job pushes only those that look different.
    PushPassUpdatesWorker.enqueue(team)

    socket =
      socket
      |> assign_rows()
      |> put_flash(:info, "ID cards saved. Cards on members' phones update in about a minute.")

    {:noreply, socket}
  end

  defp assign_rows(socket) do
    rows = EndorsementRows.for_team(socket.assigns.current_team, DateTime.utc_now())
    assign(socket, rows: rows, problems: Enum.filter(rows, &EndorsementRows.problem?/1))
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Endorsements" />
    </.breadcrumbs>
    <.heading_row>
      <h1 class="title">{@page_title}</h1>
      <:action>
        <.button id="endorsement-add" navigate={~p"/teams/#{@current_team}/endorsements/new"}>
          Add endorsement
        </.button>
      </:action>
    </.heading_row>

    <.banner
      :if={@problems != []}
      kind={:warning}
      id="endorsement-problems"
      title={
        Format.count(length(@problems), one: "1 endorsement to fix", many: "%d endorsements to fix")
      }
    >
      <ul>
        <li :for={row <- @problems}>
          <.a href={"#endorsement-#{row.id}"}>{row.name}</.a>: {problem(row)}
        </li>
      </ul>
    </.banner>

    <p class="lead">
      An endorsement is a name and the qualifications that earn it. A member with any one of
      them has the endorsement. Group rules use endorsements<span :if={@current_team.id_cards_enabled}>, and ID cards list the ones you select</span>.
    </p>

    <.empty_state :if={@rows == []} id="no-endorsements" title="No endorsements yet">
      Add one for what members earn, such as "First Aid" with every first aid course that counts.
    </.empty_state>

    <form :if={@rows != []} id="endorsements-form" phx-submit="save">
      <input type="hidden" name="ids[]" value="" />
      <.table id="endorsements" rows={@rows} row_id={&"endorsement-#{&1.id}"}>
        <:col :let={row} :if={@current_team.id_cards_enabled} label="On card" class="w-px">
          <label class="choice">
            <input
              type="checkbox"
              name="ids[]"
              value={row.id}
              checked={row.on_card}
              aria-label={"List #{row.name} on ID cards"}
            />
          </label>
        </:col>
        <:col :let={row} label="Endorsement">
          <.a navigate={~p"/teams/#{@current_team}/endorsements/#{row.id}"}>{row.name}</.a>
          <div :if={row.hidden_by != []} class="hint" id={"endorsement-#{row.id}-hidden"}>
            Cards show {names(row.hidden_by)} instead when a member has both.
          </div>
        </:col>
        <:col :let={row} label="Earned by any of">
          {Enum.join(row.qualifications, ", ")}
          <div :if={row.includes != []} class="hint" id={"endorsement-#{row.id}-includes"}>
            Or anything that earns <span phx-no-format><%= for {other, i} <- Enum.with_index(row.includes) do %><%= if i > 0 do %> or <% end %><.a navigate={~p"/teams/#{@current_team}/endorsements/#{other.id}"}>{other.name}</.a><% end %></span>
          </div>
          <div
            :for={other <- row.same_as}
            class="text-danger-text"
            id={"endorsement-#{row.id}-same-as-#{other.id}"}
          >
            Same qualifications as <.a navigate={~p"/teams/#{@current_team}/endorsements/#{other.id}"}>{other.name}</.a>.
            Use one in each group rule and delete the other.
          </div>
          <div :if={row.missing > 0} class="text-danger-text" id={"endorsement-#{row.id}-missing"}>
            {Format.count(row.missing,
              one: "1 was deleted.",
              many: "%d were deleted."
            )}
            <.a navigate={~p"/teams/#{@current_team}/endorsements/#{row.id}"}>Remove it</.a>
          </div>
          <div
            :if={EndorsementRows.empty?(row) and row.missing == 0}
            class="text-danger-text"
            id={"endorsement-#{row.id}-empty"}
          >
            No qualifications yet.
            <.a navigate={~p"/teams/#{@current_team}/endorsements/#{row.id}"}>Add one</.a>
          </div>
        </:col>
        <:col :let={row} label="Group rules">
          <span :if={row.groups == []} class="text-text-muted">None</span>
          <.group_links groups={row.groups} team={@current_team} />
        </:col>
        <:col :let={row} label="Members" align="right">
          <span class={row.members == 0 && "text-text-muted"}>{row.members}</span>
        </:col>
      </.table>
      <.form_actions :if={@current_team.id_cards_enabled}>
        <.button variant={:success}>Save ID cards</.button>
      </.form_actions>
    </form>
    """
  end

  attr :groups, :list, required: true
  attr :team, :map, required: true

  defp group_links(assigns) do
    ~H"""
    <span phx-no-format><%= for {group, i} <- Enum.with_index(@groups) do %><%= if i > 0 do %>, <% end %><.a navigate={~p"/teams/#{@team}/groups/#{group.id}"}>{group.title}</.a><% end %></span>
    """
  end

  defp problem(row) do
    cond do
      row.same_as != [] -> "same qualifications as #{names(row.same_as)}"
      row.missing > 0 -> "a qualification was deleted"
      true -> "no qualifications yet"
    end
  end

  defp names(links), do: Enum.map_join(links, " or ", & &1.name)
end
