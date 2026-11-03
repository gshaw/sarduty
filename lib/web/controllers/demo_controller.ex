defmodule Web.DemoController do
  use Web, :controller

  alias App.Accounts
  alias App.Model.DemoTeam
  alias App.Model.Team
  alias App.Operation.DeleteDemo
  alias App.Repo
  alias Web.UserAuth

  # Try a demo (#857). Opening the emailed link, or entering its code, logs the visitor in
  # and sends them to the page that builds their copy the first time. The login lasts
  # past closing the browser, as the demo lasts 7 days; deleting the demo ends it.
  def open(conn, %{"id" => id, "code" => code}), do: open_demo(conn, id, code)
  def open(conn, %{"demo" => %{"id" => id, "code" => code}}), do: open_demo(conn, id, code)
  def open(conn, _params), do: redirect(conn, to: ~p"/demo?#{[error: "code"]}")

  defp open_demo(conn, id, code) do
    with {id, ""} <- id |> to_string() |> Integer.parse(),
         %DemoTeam{} = demo <- Repo.get(DemoTeam, id),
         true <- DemoTeam.code_ok?(demo, code, DateTime.utc_now(:second)) do
      user = Accounts.get_or_create_user(demo.email)

      conn
      |> put_session(:user_return_to, ~p"/demo/building")
      |> UserAuth.log_in_user(user, remember: true)
    else
      _no -> redirect(conn, to: ~p"/demo?#{[error: "code"]}")
    end
  end

  # Delete this demo on the banner: only its visitor, or a SAR Duty admin. The visitor is
  # logged out to the home page.
  def delete(conn, %{"subdomain" => subdomain}) do
    user = conn.assigns.current_user

    with %Team{} = team <- Team.get_by(subdomain: subdomain),
         %DemoTeam{} = demo <- DemoTeam.for_team(team),
         true <- user.is_admin or String.downcase(user.email) == demo.email,
         :ok <- DeleteDemo.call(demo) do
      if user.is_admin, do: redirect(conn, to: ~p"/admin"), else: UserAuth.log_out_user(conn)
    else
      {:error, _reason} ->
        conn
        |> put_flash(:error, "The demo was not deleted. Try again in a few minutes.")
        |> redirect(to: ~p"/teams/#{subdomain}")

      _not_yours ->
        raise Web.Status.NotFound
    end
  end
end
