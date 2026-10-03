defmodule Web.StyleDraftController do
  use Web, :controller

  # A draft design system: GOV.UK's patterns, Carbon's density, light and dark. It renders
  # without the app's layouts, so no Tailwind reaches these pages and nothing else changes.
  plug :put_root_layout, false
  plug :put_layout, false

  def index(conn, _params), do: render(conn, :index)
  def tables(conn, _params), do: render(conn, :tables)
  def forms(conn, _params), do: render(conn, :forms)
end
