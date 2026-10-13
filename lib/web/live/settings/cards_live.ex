defmodule Web.Settings.CardsLive do
  use Web, :live_view_app_layout

  alias App.Model.GroupRuleClause
  alias App.ViewData.CardNames
  alias App.Worker.PushPassUpdatesWorker

  # The team comes from the URL, /teams/:subdomain/settings/cards (#153).
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    {:ok, socket |> assign(page_title: "ID cards") |> assign_names(team)}
  end

  def handle_event("save", params, socket) do
    team = socket.assigns.current_team
    known = Enum.map(socket.assigns.names, & &1.name)
    picked = params |> Map.get("names", []) |> Enum.filter(&(&1 in known))
    GroupRuleClause.set_on_card!(team.id, picked)
    # Passes already on phones change too; the job pushes only those that look different.
    %{team_id: team.id} |> PushPassUpdatesWorker.new() |> Oban.insert!()

    socket =
      socket
      |> assign_names(team)
      |> put_flash(:info, "ID cards saved. Cards on members' phones update in about a minute.")

    {:noreply, socket}
  end

  defp assign_names(socket, team),
    do: assign(socket, :names, CardNames.for_team(team, DateTime.utc_now()))

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">ID cards</h1>
      <p>
        Select the names to list on the back of members' ID cards and on the verify page. Each
        name comes from a clause in a group's rules. A member with any of its qualifications
        gets the name on their card.
      </p>

      <.empty_state :if={@names == []} id="no-names" title="No named clauses yet">
        Name a clause in a group's rules, like "First Aid", and it shows up here.
      </.empty_state>

      <form :if={@names != []} id="cards-form" phx-submit="save">
        <input type="hidden" name="names[]" value="" />
        <.table id="card-names" rows={@names} row_id={&"card-name-#{&1.index}"}>
          <:col :let={row} label="On card">
            <label class="choice">
              <input type="checkbox" name="names[]" value={row.name} checked={row.on_card} />
              {row.name}
            </label>
          </:col>
          <:col :let={row} label="Qualifications">
            {Enum.join(row.qualifications, ", ")}
            <div :if={row.missing > 0} class="text-danger-text" id={"card-name-#{row.index}-missing"}>
              {if row.missing == 1,
                do: "1 is no longer in D4H.",
                else: "#{row.missing} are no longer in D4H."}
            </div>
            <div :if={row.members == 0} class="hint" id={"card-name-#{row.index}-no-members"}>
              No member holds one.
            </div>
            <div
              :if={row.missing > 0 or row.members == 0}
              class="hint"
              id={"card-name-#{row.index}-fix"}
              phx-no-format
            >Fix in <%= for {group, j} <- Enum.with_index(row.groups) do %><%= if j > 0 do %>, <% end %><.a navigate={~p"/teams/#{@current_team}/groups/#{group.id}"}>{group.title}</.a><% end %></div>
          </:col>
          <:col :let={row} label="Members" align="right">
            <span class={row.members == 0 && "text-text-muted"}>{row.members}</span>
          </:col>
        </.table>
        <.form_actions>
          <.button variant={:success}>Save settings</.button>
        </.form_actions>
      </form>
    </div>
    """
  end
end
