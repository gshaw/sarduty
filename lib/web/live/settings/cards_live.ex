defmodule Web.Settings.CardsLive do
  use Web, :live_view_app_layout

  alias App.Model.Group
  alias App.Model.GroupRuleClause
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

  # Named clauses from every group's rules, one row per name: ticked when on cards, the
  # groups that use it, and whether those groups list different qualifications under it.
  defp assign_names(socket, team) do
    groups = team.id |> Group.get_all() |> Map.new(&{&1.d4h_group_id, &1})

    names =
      team.id
      |> GroupRuleClause.get_all_named()
      |> Enum.group_by(& &1.name)
      |> Enum.map(fn {name, clauses} -> name_row(name, clauses, groups) end)
      |> Enum.sort_by(& &1.name)

    assign(socket, :names, names)
  end

  defp name_row(name, clauses, groups) do
    %{
      name: name,
      on_card: Enum.any?(clauses, & &1.on_card),
      groups:
        clauses
        |> Enum.map(&groups[&1.d4h_group_id])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.id)
        |> Enum.sort_by(& &1.title),
      mixed: clauses |> Enum.map(&qualification_ids/1) |> Enum.uniq() |> length() > 1
    }
  end

  defp qualification_ids(clause),
    do: MapSet.new(clause.group_rule_clause_qualifications, & &1.d4h_qualification_id)

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">ID cards</h1>
      <p>
        Select the qualifications to list on the back of members' ID cards and on the verify page.
        They come from named clauses in your groups' rules.
      </p>

      <.empty_state :if={@names == []} id="no-names" title="No named clauses yet">
        Name a clause in a group's rules, like "First Aid", and it shows up here.
      </.empty_state>

      <form :if={@names != []} id="cards-form" phx-submit="save">
        <input type="hidden" name="names[]" value="" />
        <div :for={{row, i} <- Enum.with_index(@names)} id={"card-name-#{i}"} class="mb-2">
          <label class="choice">
            <input type="checkbox" name="names[]" value={row.name} checked={row.on_card} />
            {row.name}
          </label>
          <div :if={row.groups != []} class="hint ml-8" phx-no-format>
            Used by <%= for {group, j} <- Enum.with_index(row.groups) do %><%= if j > 0 do %>, <% end %><.a navigate={~p"/teams/#{@current_team}/groups/#{group.id}"}>{group.title}</.a><% end %>
          </div>
          <.warning_text :if={row.mixed} id={"card-name-#{i}-mixed"} class="ml-8 mt-1 mb-0">
            These groups list different qualifications under this name. Any of them puts it on a card.
          </.warning_text>
        </div>
        <.form_actions>
          <.button variant={:success}>Save settings</.button>
        </.form_actions>
      </form>
    </div>
    """
  end
end
