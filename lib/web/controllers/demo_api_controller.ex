defmodule Web.DemoApiController do
  use Web, :controller

  alias App.Model.DemoTeam
  alias App.Operation.CreateDemo
  alias App.Operation.DeleteDemo

  # Try a demo for agents and scripts (#857, /agents.md). POST makes a demo and answers
  # its link; opening the link logs in and builds it. `name` is optional. With the test
  # key as a bearer token it makes a test demo instead, lasting `hours` (2, at most 24),
  # outside the limits on visitors. DELETE with the link's token deletes the demo, as
  # the banner's Delete this demo does.

  def create(conn, params) do
    opts =
      if conn |> bearer() |> CreateDemo.test_key?(),
        do: [kind: :test, hours: params["hours"]],
        else: [kind: :visitor, ip: Web.VerifyLimit.client_ip(conn)]

    case params |> Map.take(["name"]) |> CreateDemo.call(opts) do
      {:ok, demo} ->
        conn
        |> put_status(:created)
        |> json(%{
          url: url(~p"/demo/open/#{DemoTeam.link_token(demo)}"),
          kind: demo.kind,
          expires_at: demo.expires_at
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        {message, _opts} = changeset.errors[:name]
        conn |> put_status(:unprocessable_entity) |> json(%{error: message})

      {:error, reason} ->
        conn |> put_status(status(reason)) |> json(%{error: CreateDemo.error_text(reason)})
    end
  end

  def delete(conn, %{"token" => token}) do
    with %DemoTeam{} = demo <- DemoTeam.from_link_token(token, DateTime.utc_now(:second)),
         :ok <- DeleteDemo.call(demo) do
      send_resp(conn, :no_content, "")
    else
      nil -> conn |> put_status(:not_found) |> json(%{error: "No demo has that link."})
      {:error, _reason} -> conn |> put_status(:bad_gateway) |> json(%{error: "Not deleted."})
    end
  end

  defp status(:limited), do: :too_many_requests
  defp status(_full_or_off), do: :service_unavailable

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> key] -> String.trim(key)
      _none -> nil
    end
  end
end
