defmodule App.RecordsStub do
  @moduledoc """
  Stands in for SAR Duty Records (docs/records.md) in tests, through the D4H adapter's
  `Req.Test` stub. Each write goes to `reply.(method, path, body)`, which returns
  `{status, json}`, and the test receives `{:records, method, path, body}` with the path
  after `/v3/team/<id>`. A read of a path in `reads` gets that list as a page; every other
  read gets an empty one, so the sync after an edit finds nothing to copy.
  """

  def stub(reply, reads \\ %{}) do
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn
      %{method: "GET"} = conn ->
        path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")
        results = Map.get(reads, path, [])
        Req.Test.json(conn, %{"results" => results, "totalSize" => length(results), "page" => 0})

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

  @doc "An activity as Records answers with one."
  def activity_json(id, attrs \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "resourceType" => "Exercise",
        "reference" => "00001",
        "referenceDescription" => "Practice",
        "published" => false,
        "address" => %{},
        "startsAt" => "2026-10-09T01:00:00Z",
        "endsAt" => "2026-10-09T03:00:00Z",
        "tags" => [],
        "owner" => %{"resourceType" => "Team", "id" => 2_000_000_000}
      },
      attrs
    )
  end

  @doc "Every Records team has these tags; letters count hours by their titles."
  def tags_json,
    do: [%{"id" => 1, "title" => "Primary Hours"}, %{"id" => 2, "title" => "Secondary Hours"}]
end
