defmodule Web.MockupSeed do
  @moduledoc """
  The made-up cast every mockup draws, and a page dumper (docs/mockups.md). A mockup's
  dump test calls `team/1`, picks the records it shows from the cast, adds only what
  the cast lacks with the app's fixtures, and ends with `dump/1`. `Web.MockupSeedTest`
  keeps it working.
  """

  import App.AccountsFixtures
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias App.Operation.SeedCoastRange

  @endpoint Web.Endpoint

  @doc """
  Coast Range SAR (App.CoastRange), the team agents' reports run on too, with every
  record a report reads. Alex Chen (alex.chen@example.com), its team admin, and Cameron
  Ruiz, a member, have users, so pages can be dumped as either. Returns a map of names
  to members, `:team`, `:alex`, `:cameron`, and `:rows`, every row by `{kind, key}` as
  App.Operation.SeedCoastRange.call/3 returns them: `cast.rows[{:activity, d4h_id}]`.
  """
  def team(attrs \\ %{}) do
    rows = SeedCoastRange.call(App.Repo, DateTime.utc_now(), attrs)
    members = for {{:member, name}, member} <- rows, into: %{}, do: {name, member}

    Map.merge(members, %{
      team: rows[{:team, :coastrange}],
      alex: user_fixture(%{email: "alex.chen@example.com"}),
      cameron: user_fixture(%{email: "cameron.ruiz@example.com"}),
      rows: rows
    })
  end

  @doc """
  The cast's latest activity titled `title`, such as "Missing hiker" or "Rope rescue
  training", for a dump test that shows one.
  """
  def activity(cast, title) do
    activities = for {{:activity, _}, %{title: ^title} = a} <- cast.rows, do: a
    Enum.max_by(activities, & &1.started_at, DateTime)
  end

  @doc "A conn logged in as `user`, for `dump/1`."
  def conn_for(user), do: Web.ConnCase.log_in_user(build_conn(), user)

  @doc "A conn with nobody logged in."
  def anonymous, do: build_conn()

  @doc """
  Renders each `{name, conn, path}` page to `name.html` in `dir`, by default the folder
  `tools/mockups/dump.sh` names in `MOCKUP_OUT`. A LiveView renders as one; a controller
  page, such as the style guide, is its `<body>`. A path that redirects raises: the conn
  can't see that page.
  """
  def dump(pages, dir \\ System.fetch_env!("MOCKUP_OUT")) do
    File.mkdir_p!(dir)

    for {name, conn, path} <- pages do
      html =
        case live(conn, path) do
          {:ok, lv, _html} -> render_async(lv)
          {:error, :nosession} -> conn |> get(path) |> html_response(200) |> body()
          other -> raise "#{name} (#{path}) was not dumped: #{inspect(other)}"
        end

      dir |> Path.join(name <> ".html") |> File.write!(html)
    end
  end

  # The page's own <style> blocks travel with its body; app.css comes from the kit.
  defp body(html) do
    [head, body] =
      Regex.run(~r{<head>(.*)</head>.*<body[^>]*>(.*)</body>}s, html, capture: :all_but_first)

    styles = ~r{<style>.*?</style>}s |> Regex.scan(head) |> Enum.map_join("\n", &hd/1)
    styles <> body
  end
end
