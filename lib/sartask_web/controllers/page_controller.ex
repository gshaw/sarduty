defmodule SartaskWeb.PageController do
  use SartaskWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
