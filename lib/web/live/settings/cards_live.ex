defmodule Web.Settings.CardsLive do
  use Web, :live_view_narrow_layout

  alias App.Model.GroupRuleClause
  alias App.Worker.PushPassUpdatesWorker

  # The team comes from the URL, /teams/:subdomain/settings/cards (#153).
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    {:ok, socket |> assign(page_title: "ID cards") |> assign_names(team)}
  end

  def handle_event("save", params, socket) do
    team = socket.assigns.current_team
    known = Map.keys(socket.assigns.names)
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

  # Named clauses from every group's rules, one entry per name, ticked when on cards.
  defp assign_names(socket, team) do
    names =
      team.id
      |> GroupRuleClause.get_all_named()
      |> Enum.group_by(& &1.name)
      |> Map.new(fn {name, clauses} -> {name, Enum.any?(clauses, & &1.on_card)} end)

    assign(socket, :names, names)
  end

  def render(assigns) do
    ~H"""
    <div>
      <.back_link navigate={~p"/teams/#{@current_team}/settings"}>Team settings</.back_link>
      <h1 class="heading">ID cards</h1>
      <p>
        Select the qualifications to list on the back of members' ID cards and on the verify page.
        They come from named clauses in your groups' rules.
      </p>

      <.empty_state :if={@names == %{}} id="no-names" title="No named clauses yet">
        Name a clause in a group's rules, like "First Aid", and it shows up here.
      </.empty_state>

      <form :if={@names != %{}} id="cards-form" phx-submit="save">
        <input type="hidden" name="names[]" value="" />
        <label :for={{name, on_card} <- Enum.sort(@names)} class="choice">
          <input type="checkbox" name="names[]" value={name} checked={on_card} />
          {name}
        </label>
        <.form_actions>
          <.button variant={:success}>Save settings</.button>
        </.form_actions>
      </form>
    </div>
    """
  end
end
