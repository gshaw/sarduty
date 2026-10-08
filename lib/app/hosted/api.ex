defmodule App.Hosted.API do
  @moduledoc """
  The hosted store as D4H's v3 API: the endpoints SAR Duty calls, plus a few D4H
  lacks so a team can be run from SAR Duty alone (docs/hosted-d4h.md).

  The D4H adapter calls it in-process for a hosted team (Req's `plug:` option), and the
  router serves it at `/d4h/v3` for anything else that speaks D4H. Either way the
  bearer key decides the team, and a path naming another team is refused.
  """

  use Plug.Router

  alias App.Hosted
  alias App.Hosted.JSON
  alias App.Hosted.Params

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason, pass: ["*/*"]
  plug :authenticate
  plug :dispatch

  @activities ~w(events exercises incidents)

  get "/v3/whoami" do
    send_json(conn, 200, JSON.whoami(conn.assigns.hosted_team))
  end

  get "/v3/team/:team_id/teams/:id" do
    with_team(conn, fn conn, team ->
      if id == Integer.to_string(team.id),
        do: send_json(conn, 200, JSON.render(team)),
        else: not_found(conn)
    end)
  end

  # No photos or documents yet: an empty list, and no member image.
  get "/v3/team/:team_id/documents" do
    with_team(conn, fn conn, _team -> send_json(conn, 200, JSON.page([], 0, 0, 0)) end)
  end

  get "/v3/team/:team_id/members/:id/image" do
    with_team(conn, fn conn, _team -> not_found(conn) end)
  end

  patch "/v3/team/:team_id/members/:id/retire" do
    with_team(conn, fn conn, team ->
      attrs =
        case conn.body_params do
          %{"direction" => "UNRETIRE"} -> %{status: "OPERATIONAL", ends_at: nil}
          body -> %{status: "RETIRED", ends_at: retire_date(body)}
        end

      respond(conn, Hosted.update(team, "members", integer(id), attrs))
    end)
  end

  post "/v3/team/:team_id/:resource/:id/publish" when resource in @activities do
    with_team(conn, fn conn, team ->
      attrs = %{published: conn.body_params["published"] == true}
      respond(conn, Hosted.update(team, resource, integer(id), attrs))
    end)
  end

  post "/v3/team/:team_id/:resource/:id/tags" when resource in @activities do
    with_team(conn, fn conn, team ->
      tag_ids = conn.body_params["tagIds"]

      if is_list(tag_ids) and Enum.all?(tag_ids, &is_integer/1),
        do: respond(conn, Hosted.set_tags(team, resource, integer(id), tag_ids)),
        else: bad_request(conn, "tagIds must be a list of ids.")
    end)
  end

  get "/v3/team/:team_id/:resource" do
    with_resource(conn, resource, fn conn, team ->
      params = conn.query_params
      {rows, total} = Hosted.list(team, resource, params)
      {page, size} = Hosted.paging(params)
      send_json(conn, 200, JSON.page(rows, total, page, size))
    end)
  end

  get "/v3/team/:team_id/:resource/:id" do
    with_resource(conn, resource, fn conn, team ->
      case Hosted.get(team, resource, integer(id)) do
        nil -> not_found(conn)
        row -> send_json(conn, 200, JSON.render(row))
      end
    end)
  end

  post "/v3/team/:team_id/:resource" do
    with_resource(conn, resource, fn conn, team ->
      attrs = Params.to_attrs(resource, conn.body_params)
      respond(conn, Hosted.create(team, resource, attrs))
    end)
  end

  patch "/v3/team/:team_id/:resource/:id" do
    with_resource(conn, resource, fn conn, team ->
      attrs = Params.to_attrs(resource, conn.body_params)
      respond(conn, Hosted.update(team, resource, integer(id), attrs))
    end)
  end

  delete "/v3/team/:team_id/:resource/:id" do
    with_resource(conn, resource, fn conn, team ->
      case Hosted.delete(team, resource, integer(id)) do
        {:ok, _row} -> send_json(conn, 200, %{})
        error -> respond(conn, error)
      end
    end)
  end

  match _ do
    not_found(conn)
  end

  defp authenticate(conn, _opts) do
    key =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> key | _] -> String.trim(key)
        _none -> nil
      end

    case Hosted.get_team_by_key(key) do
      nil -> conn |> send_json(401, JSON.error(401, "Unauthorized")) |> halt()
      team -> assign(conn, :hosted_team, team)
    end
  end

  # The key's own team only, as D4H refuses a team the key can't see.
  defp with_team(conn, fun) do
    team = conn.assigns.hosted_team

    if conn.path_params["team_id"] == Integer.to_string(team.id),
      do: fun.(conn, team),
      else: send_json(conn, 403, JSON.error(403, "Forbidden"))
  rescue
    error in [ArgumentError, MatchError, FunctionClauseError] ->
      bad_request(conn, Exception.message(error))
  end

  defp with_resource(conn, resource, fun) do
    if resource in Hosted.resources(),
      do: with_team(conn, fun),
      else: not_found(conn)
  end

  defp respond(conn, {:ok, row}), do: send_json(conn, 200, JSON.render(row))
  defp respond(conn, {:error, :not_found}), do: not_found(conn)
  defp respond(conn, {:error, :not_allowed}), do: bad_request(conn, "Members can't be deleted.")

  defp respond(conn, {:error, %Ecto.Changeset{} = changeset}),
    do: bad_request(conn, describe(changeset))

  defp respond(conn, {:error, message}) when is_binary(message), do: bad_request(conn, message)

  defp not_found(conn), do: send_json(conn, 404, JSON.error(404, "Not Found"))
  defp bad_request(conn, title), do: send_json(conn, 400, JSON.error(400, title))

  # "name can't be blank; ends_at must be after the start"
  defp describe(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
    |> Enum.join("; ")
  end

  defp retire_date(%{"date" => date}) when is_binary(date) do
    case DateTime.from_iso8601(date) do
      {:ok, time, _offset} -> DateTime.truncate(time, :second)
      _error -> DateTime.utc_now(:second)
    end
  end

  defp retire_date(_body), do: DateTime.utc_now(:second)

  defp integer(id), do: String.to_integer(id)

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
