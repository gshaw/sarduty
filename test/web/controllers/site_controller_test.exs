defmodule Web.SiteControllerTest do
  # Files crawlers, agents, and link previews look for (#824).
  use Web.ConnCase, async: true

  @static Path.expand("../../../priv/static", __DIR__)

  defp verify_conn(conn), do: Map.put(conn, :host, Web.VerifyHost.host())

  for {name, host_url} <- [app: &Web.Endpoint.url/0, verify: &Web.VerifyHost.url/0] do
    test "security.txt on the #{name} host", %{conn: conn} do
      conn = if unquote(name) == :verify, do: verify_conn(conn), else: conn
      conn = get(conn, "/.well-known/security.txt")
      text = response(conn, 200)

      assert response_content_type(conn, :text) =~ "text/plain"
      assert text =~ "Contact: mailto:support@sarduty.com\n"
      assert text =~ "Canonical: #{unquote(host_url).()}/.well-known/security.txt\n"

      [_, expires] = Regex.run(~r/^Expires: (\S+)$/m, text)
      {:ok, expires, 0} = DateTime.from_iso8601(expires)
      assert DateTime.after?(expires, DateTime.utc_now())
    end

    test "/security.txt goes to the well-known one on the #{name} host", %{conn: conn} do
      conn = if unquote(name) == :verify, do: verify_conn(conn), else: conn
      assert conn |> get("/security.txt") |> redirected_to() == "/.well-known/security.txt"
    end
  end

  test "robots.txt blocks nothing" do
    text = @static |> Path.join("robots.txt") |> File.read!()
    assert text =~ "User-agent: *"
    refute text =~ ~r/^Disallow/im
  end

  test "llms.txt is the agents page, and lists the style guide", %{conn: conn} do
    text = conn |> get("/llms.txt") |> response(200)

    assert text =~ Web.AgentsLive.markdown()
    assert text =~ "#{Web.Endpoint.url()}/styles)"
  end

  test "the root icons exist and are served" do
    for file <- ~w(apple-touch-icon.png apple-touch-icon-precomposed.png manifest.webmanifest) do
      assert @static |> Path.join(file) |> File.exists?(), file
      assert file in Web.static_paths(), file
    end
  end

  test "the manifest's icons exist" do
    manifest = @static |> Path.join("manifest.webmanifest") |> File.read!() |> JSON.decode!()

    for %{"src" => "/" <> src} <- manifest["icons"] do
      assert @static |> Path.join(src) |> File.exists?(), src
    end
  end

  test "link previews are small: title, description, and site name, no image", %{conn: conn} do
    html = conn |> get(~p"/privacy") |> html_response(200)

    for property <- ~w(og:title og:description og:site_name) do
      assert html =~ ~s(<meta property="#{property}" content=")
    end

    refute html =~ "og:image"
  end
end
