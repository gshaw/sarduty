defmodule Web.MockupSeed do
  @moduledoc """
  The made-up cast every mockup draws, and a page dumper (docs/mockups.md). A mockup's
  dump test calls `team/1`, adds what its topic needs with the app's fixtures, and ends
  with `dump/1`. `Web.MockupSeedTest` keeps it working.
  """

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias App.Repo

  @endpoint Web.Endpoint

  # cspell:ignore CRSAR Kowal Noor Priya
  @cast ~w(Avery_Chen Blake_Morrison Cameron_Ruiz Casey_Dhillon Dana_Kowal Drew_Patel
    Eli_Haddad Harper_Nguyen Jordan_Lee Noor_Aziz Priya_Nair Quinn_Laval Riley_Okafor Sam_Rivera)

  @doc """
  Coast Range SAR, its admin Alex Chen (alex.chen@example.com), and the cast as members.
  Cameron Ruiz also has a user, so pages can be dumped as a member. Returns a map of
  names to members, plus `:team`, `:alex`, and `:cameron`.
  """
  def team(attrs \\ %{}) do
    team =
      %{
        name: "Coast Range SAR",
        legal_name: "Coast Range Search and Rescue Society",
        abbreviated_name: "CRSAR",
        subdomain: "coastrange"
      }
      |> Map.merge(attrs)
      |> member_logins_team_fixture()
      |> Ecto.Changeset.change(d4h_synced_at: DateTime.utc_now())
      |> Repo.update!()

    alex = user_fixture(%{email: "alex.chen@example.com"})

    manager_fixture(team, %{
      name: "Alex Chen",
      email: alex.email,
      ref_id: "112",
      phone: "604-555-0112"
    })

    cameron = user_fixture(%{email: "cameron.ruiz@example.com"})

    members =
      for {n, i} <- Enum.with_index(@cast), into: %{} do
        name = String.replace(n, "_", " ")
        slug = name |> String.downcase() |> String.replace(" ", ".")

        {name,
         member_fixture(team, %{
           name: name,
           email: "#{slug}@example.com",
           phone: "604-555-01#{20 + i}",
           ref_id: "#{130 + i}",
           d4h_permission: 3
         })}
      end

    Map.merge(members, %{team: team, alex: alex, cameron: cameron})
  end

  @doc "A conn logged in as `user`, for `dump/1`."
  def conn_for(user), do: Web.ConnCase.log_in_user(build_conn(), user)

  @doc "A conn with nobody logged in."
  def anonymous, do: build_conn()

  @doc """
  Renders each `{name, conn, path}` LiveView to `name.html` in `dir`, by default the
  folder `tools/mockups/dump.sh` names in `MOCKUP_OUT`. A path that redirects raises:
  the conn can't see that page.
  """
  def dump(pages, dir \\ System.fetch_env!("MOCKUP_OUT")) do
    File.mkdir_p!(dir)

    for {name, conn, path} <- pages do
      case live(conn, path) do
        {:ok, lv, _html} -> dir |> Path.join(name <> ".html") |> File.write!(render_async(lv))
        other -> raise "#{name} (#{path}) was not dumped: #{inspect(other)}"
      end
    end
  end
end
