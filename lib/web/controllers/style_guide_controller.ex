defmodule Web.StyleGuideController do
  use Web, :controller

  alias Web.StyleGuideHTML

  # The design system: GOV.UK's patterns, Carbon's density, light and dark. It renders
  # without the app's layouts, so it shows the tokens and components on their own.
  plug :put_root_layout, false
  plug :put_layout, false

  def index(conn, _params), do: render(conn, :index_page)

  def show(conn, %{"page" => slug}) do
    case StyleGuideHTML.find(slug) do
      {:group, group} -> render(conn, :group_page, group: group)
      {:page, template} -> render(conn, template)
      nil -> raise Web.Status.NotFound
    end
  end
end
