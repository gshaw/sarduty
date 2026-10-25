defmodule Web.StyleGuideController do
  use Web, :controller

  alias Web.StyleGuideHTML

  # The design system: GOV.UK's patterns, Carbon's density, light and dark. Its own frame
  # under the app's top bar, so the team switcher is there as on any page outside a team.
  plug :put_root_layout, html: {StyleGuideHTML, :frame}
  plug :put_layout, false
  plug :assign_menus

  def index(conn, _params), do: render(conn, :index_page, current: :index)

  def show(conn, %{"page" => slug}) do
    case StyleGuideHTML.find(slug) do
      {:group, {group, _title, _about, _pages} = g} ->
        render(conn, :group_page, group: g, current: group)

      {:page, page} ->
        render(conn, StyleGuideHTML.template(page), current: page)

      nil ->
        raise Web.Status.NotFound
    end
  end

  defp assign_menus(conn, opts), do: Web.UserAuth.assign_menus(conn, opts)
end
