defmodule Web.Settings.CardsLive do
  use Web, :live_view_narrow_layout

  alias App.Model.GroupRuleClause
  alias App.Worker.PushPassUpdatesWorker

  def mount(_params, _session, socket) do
    team = socket.assigns.current_user.team

    socket =
      if team == nil do
        push_navigate(socket, to: ~p"/settings")
      else
        socket |> assign(page_title: "ID Cards") |> assign_names(team)
      end

    {:ok, socket}
  end

  def handle_event("save", params, socket) do
    team = socket.assigns.current_user.team
    known = Map.keys(socket.assigns.names)
    picked = params |> Map.get("names", []) |> Enum.filter(&(&1 in known))
    GroupRuleClause.set_on_card!(team.id, picked)
    # Passes already on phones change too; the job pushes only those that look different.
    %{team_id: team.id} |> PushPassUpdatesWorker.new() |> Oban.insert!()

    socket =
      socket
      |> assign_names(team)
      |> put_flash(:info, "Saved. Passes on members' phones update in a minute or so.")

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
      <p>
        <.a navigate={~p"/settings"}>← Settings</.a>
      </p>
      <h1 class="heading">ID cards</h1>
      <p>
        Pick the qualifications to list on the back of members' ID cards and on the check page.
        They come from named clauses in your groups' rules.
      </p>

      <p :if={@names == %{}} id="no-names" class="mt-p">
        No named clauses yet. Name a clause in a group's rules, like "First Aid", and it shows up here.
      </p>

      <form :if={@names != %{}} id="cards-form" phx-submit="save" class="mt-p">
        <input type="hidden" name="names[]" value="" />
        <label :for={{name, on_card} <- Enum.sort(@names)} class="flex items-center gap-2 my-2">
          <input type="checkbox" name="names[]" value={name} checked={on_card} />
          {name}
        </label>
        <.form_actions>
          <.button variant={:success}>Save</.button>
        </.form_actions>
      </form>
    </div>
    """
  end
end
