defmodule Web.PageDescriptionTest do
  use Web.ConnCase, async: true

  # Each public page has its own meta description, for search results and link previews.
  # App pages share the layout's, as the login code step does.
  @public ~w(/ /terms /privacy /changelog /agents /agents/reports /signup /login)

  test "each public page describes itself", %{conn: conn} do
    default = description(conn, "/login/code?email=pat@example.com")

    descriptions =
      for path <- @public do
        text = description(conn, path)
        assert text != default, "#{path} has the layout's description"
        text
      end

    assert descriptions == Enum.uniq(descriptions)
  end

  defp description(conn, path) do
    [_, text] =
      Regex.run(
        ~r/<meta name="description" content="([^"]*)"/,
        html_response(get(conn, path), 200)
      )

    text
  end
end
