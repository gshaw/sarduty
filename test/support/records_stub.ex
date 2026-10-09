defmodule App.RecordsStub do
  @moduledoc """
  Stands in for SAR Duty Records (docs/records.md) in tests, through the D4H adapter's
  `Req.Test` stub. Each write goes to `reply.(method, path, body)`, which returns
  `{status, json}`, and the test receives `{:records, method, path, body}` with the path
  after `/v3/team/<id>`. Every read gets an empty page, so the sync after an edit finds
  nothing to copy.
  """

  def stub(reply) do
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn
      %{method: "GET"} = conn ->
        Req.Test.json(conn, %{"results" => [], "totalSize" => 0, "page" => 0})

      conn ->
        write(conn, test, reply)
    end)
  end

  defp write(conn, test, reply) do
    path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    json = if body == "", do: nil, else: Jason.decode!(body)
    send(test, {:records, conn.method, path, json})
    {status, response} = reply.(conn.method, path, json)
    conn |> Plug.Conn.put_status(status) |> Req.Test.json(response)
  end

  @doc "A member as Records answers with one."
  def member_json(id, attrs \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "name" => "Casey New",
        "email" => %{"value" => "casey@example.com"},
        "mobile" => %{"phone" => nil},
        "permission" => "MEMBER",
        "status" => "OPERATIONAL",
        "owner" => %{"resourceType" => "Team", "id" => 2_000_000_000}
      },
      attrs
    )
  end
end
