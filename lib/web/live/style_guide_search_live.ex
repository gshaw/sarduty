defmodule Web.StyleGuideSearchLive do
  @moduledoc """
  The style guide's search, in its top bar: the app's search box (Web.Components.Search),
  finding the guide's pages and their sections from Web.StyleGuideSearch. The guide's
  pages are rendered by a controller, so its frame live_renders this, and styles.js
  connects it with the app's Search hook. Logged in or not, as the guide is.
  """
  use Phoenix.LiveView

  alias Web.Components.Search

  @none_help [
    "Search looks at every word on the guide's pages, examples included. Check the spelling, or try fewer words."
  ]

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, query: "", groups: [], recent: []), layout: false}

  # The hook sends the browser's recent picks when it mounts.
  def handle_event("recent", %{"keys" => keys}, socket),
    do: {:noreply, assign(socket, recent: Web.StyleGuideSearch.recent(keys))}

  def handle_event("search", %{"q" => query}, socket),
    do: {:noreply, assign(socket, query: query, groups: Web.StyleGuideSearch.run(query))}

  # Enter with nothing picked: the best result, as the hook picks the first one. A full
  # page load, as the guide's pages aren't LiveViews and a text fragment needs one.
  def handle_event("open", %{"q" => query}, socket) do
    case Web.StyleGuideSearch.run(query) do
      [%{hits: [%{path: path} | _rest]} | _groups] -> {:noreply, redirect(socket, to: path)}
      groups -> {:noreply, assign(socket, query: query, groups: groups)}
    end
  end

  def render(assigns) do
    assigns = assign(assigns, none_help: @none_help)

    ~H"""
    <Search.search_box
      id="search"
      query={@query}
      groups={@groups}
      recent={@recent}
      recent_key="sarduty:styles-search-recent"
      placeholder="Search the style guide"
      hint="Find a page or section by any word on it, examples included."
      none_help={@none_help}
      live_links={false}
      word_starts={true}
    />
    """
  end
end
