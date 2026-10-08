defmodule Web.ErrorHTMLTest do
  use Web.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html" do
    assert render_to_string(Web.ErrorHTML, "404", "html", []) =~ "Not found"
  end

  test "every error page has its code and description as its title" do
    for {code, description} <- [
          {"404", "Not found"},
          {"429", "Too many requests"},
          {"500", "Internal server error"}
        ] do
      html = render_to_string(Web.ErrorHTML, code, "html", [])
      assert html =~ ~r/<title[^>]*>\s*#{code} #{description}\s*· SAR Duty\s*<\/title>/
    end
  end

  test "renders 500.html" do
    assert render_to_string(Web.ErrorHTML, "500", "html", []) =~ "Internal server error"
  end
end
