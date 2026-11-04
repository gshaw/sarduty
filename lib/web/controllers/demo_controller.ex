defmodule Web.DemoController do
  use Web, :controller

  alias App.Model.DemoTeam
  alias App.Operation.DeleteDemo
  alias App.Repo
  alias Web.UserAuth

  # Try a demo (#857). The link logs the browser in as the demo's visitor, then opens it,
  # building it the first time. It works for the demo's life, on any browser, so an
  # agent can start one and hand the link to the person it's helping. The login lasts
  # past closing the browser; deleting the demo ends it.
  def open(conn, %{"token" => token}) do
    case DemoTeam.from_link_token(token, DateTime.utc_now(:second)) do
      %DemoTeam{} = demo ->
        user = Repo.get!(App.Accounts.User, demo.user_id)

        conn
        |> put_session(:user_return_to, ~p"/demo/building")
        |> UserAuth.log_in_user(user, remember: true)

      nil ->
        conn
        |> put_flash(:error, "That demo has ended or was deleted. Start a new one.")
        |> redirect(to: ~p"/demo")
    end
  end

  # Delete this demo on the banner: its visitor, or a SAR Duty admin. The visitor is
  # logged out to the home page.
  def delete(conn, _params) do
    user = conn.assigns.current_user

    with %DemoTeam{} = demo <- DemoTeam.for_team(conn.assigns.current_team),
         true <- user.is_admin or user.id == demo.user_id,
         :ok <- DeleteDemo.call(demo) do
      if user.is_admin, do: redirect(conn, to: ~p"/admin"), else: UserAuth.log_out_user(conn)
    else
      {:error, _reason} ->
        conn
        |> put_flash(:error, "The demo was not deleted. Try again in a few minutes.")
        |> redirect(to: ~p"/teams/#{conn.assigns.current_team}")

      _not_yours ->
        raise Web.Status.NotFound
    end
  end
end
