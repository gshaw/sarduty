defmodule Web.StyleDraftController do
  use Web, :controller

  alias Web.StyleDraftHTML

  # A draft design system: GOV.UK's patterns, Carbon's density, light and dark. It renders
  # without the app's layouts, so no Tailwind reaches these pages and nothing else changes.
  plug :put_root_layout, false
  plug :put_layout, false

  def index(conn, _params), do: render(conn, :index)

  def show(conn, %{"page" => slug}) do
    page =
      Enum.find_value(StyleDraftHTML.pages(), fn {_group, pages} ->
        Enum.find_value(pages, fn {page, _title} -> Atom.to_string(page) == slug && page end)
      end)

    if page && page != :index, do: render(conn, page), else: raise(Web.Status.NotFound)
  end
end
