defmodule Web.Components.SearchBox do
  @moduledoc """
  The top bar's search on a team's pages (#473): Web.Components.Search's markup, searching
  as you type. It lives in the layout, so every team page has it, and going to another page
  starts it fresh. Pass the team, `team_admin?` and `member?` as the page assigned them,
  and the side navigation's `sections`, which are the pages it finds, and `user_id`, whose
  recent picks the browser keeps.
  """
  use Web, :live_component

  alias Web.Components.Search

  def mount(socket), do: {:ok, assign(socket, query: "", groups: [], recent: [])}

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       kinds: Web.Search.kinds(assigns.team, assigns.team_admin?, assigns.member?),
       # Per person and team, so a shared iPad doesn't show the last person's picks.
       recent_key: "sarduty:search-recent:#{assigns.user_id}:#{assigns.team.subdomain}"
     )}
  end

  # The hook sends the browser's recent picks when it mounts.
  def handle_event("recent", %{"keys" => keys}, socket) do
    %{team: team, team_admin?: team_admin?, member?: member?, sections: sections} =
      socket.assigns

    recent =
      Web.Search.recent(team, keys,
        team_admin?: team_admin?,
        member?: member?,
        sections: sections
      )

    {:noreply, assign(socket, recent: recent)}
  end

  def handle_event("search", %{"q" => query}, socket),
    do: {:noreply, assign(socket, query: query, groups: run(socket, query))}

  # Enter with nothing picked: the best result, as the hook picks the first one.
  def handle_event("open", %{"q" => query}, socket) do
    case run(socket, query) do
      [%{hits: [%{path: path} | _rest]} | _groups] -> {:noreply, push_navigate(socket, to: path)}
      groups -> {:noreply, assign(socket, query: query, groups: groups)}
    end
  end

  defp run(socket, query) do
    %{team: team, team_admin?: team_admin?, member?: member?, sections: sections} =
      socket.assigns

    Web.Search.run(team, query, team_admin?: team_admin?, member?: member?, sections: sections)
  end

  def render(assigns) do
    ~H"""
    <div class="contents">
      <Search.search_box
        id={@id}
        query={@query}
        groups={@groups}
        recent={@recent}
        recent_key={@recent_key}
        kinds={@kinds}
        team={@team}
        target={@myself}
      />
    </div>
    """
  end
end
