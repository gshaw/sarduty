defmodule App.Model.AgentClientTest do
  # Which return addresses an agent may use, and the name the Allow page shows (#761).
  use ExUnit.Case, async: true

  alias App.Model.AgentClient

  describe "redirect_kind/1" do
    test "a listed web agent is matched by its whole address" do
      assert AgentClient.redirect_kind("https://claude.ai/api/mcp/auth_callback") ==
               {:web, "Claude"}

      assert AgentClient.redirect_kind("https://claude.com/api/mcp/auth_callback") ==
               {:web, "Claude"}

      assert AgentClient.redirect_kind("https://chatgpt.com/connector_platform_oauth_redirect") ==
               {:web, "ChatGPT"}

      assert AgentClient.redirect_kind("https://claude.ai/other") == {:unknown, "claude.ai"}
    end

    test "the admin's own computer is always allowed" do
      for uri <- [
            "http://localhost:33418/callback",
            "http://127.0.0.1:6274/oauth/callback",
            "http://[::1]:8080/cb",
            "vscode://vscode.github-authentication/did-authenticate",
            "cursor://anysphere.cursor-retrieval/oauth/callback"
          ] do
        assert AgentClient.redirect_kind(uri) == :local, uri
      end
    end

    test "another https address is unknown, by its host" do
      assert AgentClient.redirect_kind("https://agent.example.net/cb") ==
               {:unknown, "agent.example.net"}
    end

    test "anything else is invalid" do
      for uri <- [
            "javascript:alert(1)",
            "data:text/html,hi",
            "file:///etc/passwd",
            "http://agent.example.net/cb",
            "https://claude.ai/api/mcp/auth_callback#x",
            "http://localhost:3000/cb#frag",
            "not a url",
            nil
          ] do
        assert AgentClient.redirect_kind(uri) == :invalid, inspect(uri)
      end
    end
  end

  describe "display_name/2" do
    test "a web agent gets the list's name, whatever it calls itself" do
      client = %AgentClient{name: "Totally Claude"}
      uri = "https://chatgpt.com/connector_platform_oauth_redirect"
      assert AgentClient.display_name(client, uri) == "ChatGPT"
    end

    test "a local agent names itself, cut at 40, or An AI agent" do
      uri = "http://localhost:3000/cb"
      assert AgentClient.display_name(%AgentClient{name: " Claude Code "}, uri) == "Claude Code"
      assert AgentClient.display_name(%AgentClient{name: nil}, uri) == "An AI agent"
      assert AgentClient.display_name(%AgentClient{name: "  "}, uri) == "An AI agent"

      long = String.duplicate("x", 60)
      name = AgentClient.display_name(%AgentClient{name: long}, uri)
      assert String.length(name) == 40
    end
  end

  describe "build/2" do
    test "keeps the name and return addresses" do
      params = %{"client_name" => "Claude Code", "redirect_uris" => ["http://localhost:1/cb"]}
      assert {:ok, changeset} = AgentClient.build(params, "id")
      assert changeset.data.name == "Claude Code"
      assert changeset.data.redirect_uris == ["http://localhost:1/cb"]
    end

    test "keeps an unknown https address, for the refused page to name" do
      params = %{"redirect_uris" => ["https://agent.example.net/cb"]}
      assert {:ok, _changeset} = AgentClient.build(params, "id")
    end

    test "refuses no addresses, or one the refused page can't name" do
      assert {:error, _} = AgentClient.build(%{}, "id")
      assert {:error, _} = AgentClient.build(%{"redirect_uris" => []}, "id")
      assert {:error, _} = AgentClient.build(%{"redirect_uris" => "http://localhost/cb"}, "id")

      assert {:error, _} =
               AgentClient.build(%{"redirect_uris" => ["javascript:alert(1)"]}, "id")
    end
  end
end
