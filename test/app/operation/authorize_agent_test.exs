defmodule App.Operation.AuthorizeAgentTest do
  # Reading an agent's authorize request (#761). check/3 is pure.
  use ExUnit.Case, async: true

  alias App.Model.AgentClient
  alias App.Operation.AuthorizeAgent

  @mcp_url "https://sarduty.com/teams/coastrange/mcp"
  @claude "https://claude.ai/api/mcp/auth_callback"
  @challenge String.duplicate("a", 43)

  defp client(uris \\ [@claude]),
    do: %AgentClient{id: 1, client_id: "c1", name: "Fake", redirect_uris: uris}

  defp params(extra \\ %{}) do
    Map.merge(
      %{
        "client_id" => "c1",
        "redirect_uri" => @claude,
        "response_type" => "code",
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "state" => "abc",
        "resource" => @mcp_url
      },
      extra
    )
  end

  test "a good request from a listed web agent, named from the list" do
    assert {:ok, request} = AuthorizeAgent.check(params(), client(), @mcp_url)
    assert request.name == "Claude"
    assert request.redirect_uri == @claude
    assert request.state == "abc"
    assert request.code_challenge == @challenge
  end

  test "an unknown client id, or an address it didn't register, has nowhere to go back" do
    assert {:bad_link, _} = AuthorizeAgent.check(params(), nil, @mcp_url)

    other = params(%{"redirect_uri" => "http://localhost:1/cb"})
    assert {:bad_link, _} = AuthorizeAgent.check(other, client(), @mcp_url)
  end

  test "a client with one address may leave it out" do
    without = Map.delete(params(), "redirect_uri")
    assert {:ok, request} = AuthorizeAgent.check(without, client(), @mcp_url)

    assert request.redirect_uri == @claude
  end

  test "a web agent not on the list is refused by its host" do
    uri = "https://agent.example.net/cb"
    request = params(%{"redirect_uri" => uri})

    assert AuthorizeAgent.check(request, client([uri]), @mcp_url) ==
             {:unknown_agent, "agent.example.net"}
  end

  test "a known agent's bad request goes back to it with the error" do
    for {extra, error} <- [
          {%{"response_type" => "token"}, "unsupported_response_type"},
          {%{"code_challenge" => nil}, "invalid_request"},
          {%{"code_challenge" => "short"}, "invalid_request"},
          {%{"code_challenge_method" => "plain"}, "invalid_request"},
          {%{"resource" => "https://sarduty.com/teams/other/mcp"}, "invalid_target"}
        ] do
      assert {:redirect, url} = extra |> params() |> AuthorizeAgent.check(client(), @mcp_url)
      query = url |> URI.parse() |> Map.get(:query) |> URI.decode_query()
      assert String.starts_with?(url, @claude <> "?")
      assert query["error"] == error
      assert query["state"] == "abc"
    end
  end

  test "resource is optional, and a trailing slash is the same address" do
    without = Map.delete(params(), "resource")
    slash = params(%{"resource" => @mcp_url <> "/"})
    assert {:ok, _} = AuthorizeAgent.check(without, client(), @mcp_url)
    assert {:ok, _} = AuthorizeAgent.check(slash, client(), @mcp_url)
  end

  test "Cancel sends the agent access denied, keeping its own query" do
    request = %{redirect_uri: "http://localhost:1/cb?session=9", state: "abc"}

    query = request |> AuthorizeAgent.deny_url() |> URI.parse() |> Map.get(:query)

    assert URI.decode_query(query) == %{
             "session" => "9",
             "error" => "access_denied",
             "state" => "abc"
           }
  end
end
