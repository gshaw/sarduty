defmodule Web.MapImageControllerTest do
  use Web.ConnCase

  alias App.Adapter.Mapbox
  alias Web.MapImage

  @path "styles/v1/mapbox/dark-v11/static/-123.1,49.7,10,0/640x480@2x"

  test "a signed key sends Mapbox's image on, with the token added here", %{conn: conn} do
    Req.Test.stub(Mapbox, fn conn ->
      assert conn.request_path == "/" <> @path
      assert conn.query_params["access_token"]

      conn
      |> Plug.Conn.put_resp_content_type("image/png", nil)
      |> Plug.Conn.put_resp_header("cache-control", "max-age=43200,s-maxage=7200")
      |> Plug.Conn.send_resp(200, "PNG")
    end)

    url = MapImage.url(@path)
    refute url =~ "access_token"

    conn = get(conn, url)
    assert response(conn, 200) == "PNG"
    assert get_resp_header(conn, "content-type") == ["image/png"]
    assert get_resp_header(conn, "cache-control") == ["max-age=43200,s-maxage=7200"]
  end

  test "an altered key is not found, and Mapbox isn't called", %{conn: conn} do
    "/maps/" <> key = MapImage.url(@path)
    [protected, _payload, signature] = String.split(key, ".")
    other = Base.url_encode64("geocoding/v5/mapbox.places/x.json", padding: false)

    assert_error_sent 404, fn -> get(conn, "/maps/#{protected}.#{other}.#{signature}") end
    assert_error_sent 404, fn -> get(conn, "/maps/nonsense") end
  end

  test "a Mapbox failure is a bad gateway", %{conn: conn} do
    Req.Test.stub(Mapbox, &Plug.Conn.send_resp(&1, 403, ~s({"message":"Forbidden"})))

    assert conn |> get(MapImage.url(@path)) |> response(502) == ""
  end
end
