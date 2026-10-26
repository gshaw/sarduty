defmodule Web.StaticChangedTest do
  # Not async: it changes the endpoint's asset manifest, which every test reads.
  use Web.ConnCase, async: false

  import Phoenix.LiveViewTest

  @old "http://www.example.com/assets/js/app-0ld.js"
  @new "http://www.example.com/assets/js/app-n3w.js"

  setup do
    before = Web.Endpoint.config(:cache_static_manifest_latest)
    latest = %{"assets/js/app.js" => "assets/js/app-n3w.js"}
    Phoenix.Config.put(Web.Endpoint, :cache_static_manifest_latest, latest)
    on_exit(fn -> Phoenix.Config.put(Web.Endpoint, :cache_static_manifest_latest, before) end)
  end

  defp tab(conn, static, params) do
    put_connect_params(conn, Map.merge(%{"_track_static" => [static], "_mounts" => 0}, params))
  end

  test "going to another page with old assets loads it in full", %{conn: conn} do
    conn = tab(conn, @old, %{"_live_referer" => "http://www.example.com/"})

    assert {:error, {:redirect, %{to: "http://www.example.com/login"}}} = live(conn, ~p"/login")
  end

  # The test client always sends a first mount, so a reconnect is checked here.
  test "a reconnect is not going to another page" do
    referer = "http://www.example.com/"

    assert Web.StaticChanged.navigation?(%{"_live_referer" => referer, "_mounts" => 0})
    refute Web.StaticChanged.navigation?(%{"_live_referer" => referer, "_mounts" => 1})
    refute Web.StaticChanged.navigation?(%{"_mounts" => 0})
  end

  test "a page that just loaded with old assets offers a reload", %{conn: conn} do
    {:ok, lv, _html} = live(tab(conn, @old, %{}), ~p"/login")

    assert has_element?(lv, ~s(#static-changed-reload[href="http://www.example.com/login"]))
  end

  test "a page with the latest assets says nothing", %{conn: conn} do
    conn = tab(conn, @new, %{"_live_referer" => "http://www.example.com/"})

    {:ok, lv, _html} = live(conn, ~p"/login")

    refute has_element?(lv, "#static-changed")
  end
end
