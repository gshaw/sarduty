defmodule App.Adapter.FileStoreTest do
  # Not async: some tests change the store, which is the app's config.
  use ExUnit.Case

  alias App.Adapter.FileStore
  alias App.FileStoreOff

  defp org, do: System.unique_integer([:positive])
  defp logo_key(id), do: FileStore.key(:orgs, id, :logo, nil, "logo.png")

  describe "key/5" do
    test "builds the key for each kind" do
      assert FileStore.key(:orgs, 4, :logo, nil, "logo.png") == "orgs/4/logo/logo.png"

      assert FileStore.key(:site, nil, :integration_test, "k3f9a2b1c0", "check.txt") ==
               "site/integration-test/k3f9a2b1c0/check.txt"
    end

    test "refuses a kind it doesn't know, the wrong owner, and a missing or extra token" do
      assert_raise KeyError, fn -> FileStore.key(:orgs, 4, :photo, nil, "a.jpg") end
      assert_raise ArgumentError, fn -> FileStore.key(:teams, 4, :logo, nil, "logo.png") end

      assert_raise ArgumentError, fn ->
        FileStore.key(:site, nil, :integration_test, nil, "a.txt")
      end

      assert_raise ArgumentError, fn -> FileStore.key(:orgs, 4, :logo, "k3f9a2b1c0", "a.png") end
    end

    test "new_token/0 is random and fits in a key" do
      token = FileStore.new_token()
      assert token != FileStore.new_token()
      assert FileStore.key(:site, nil, :integration_test, token, "a.txt") =~ token
    end
  end

  describe "on disk" do
    test "puts a file, gets it back, and deletes it" do
      key = logo_key(org())
      assert FileStore.store() == :disk
      assert FileStore.get(key) == {:error, :not_found}

      assert FileStore.put(key, "first") == :ok
      assert FileStore.get(key) == {:ok, "first"}

      # A put takes the place of what was there.
      assert FileStore.put(key, "second") == :ok
      assert FileStore.get(key) == {:ok, "second"}

      assert FileStore.delete(key) == :ok
      assert FileStore.get(key) == {:error, :not_found}
      # One that is gone already is fine.
      assert FileStore.delete(key) == :ok
    end

    test "tags/1 says what the kind is tagged" do
      key = FileStore.key(:site, nil, :integration_test, FileStore.new_token(), "a.txt")
      :ok = FileStore.put(key, "bytes")
      assert FileStore.tags(key) == {:ok, %{"expires" => "2d"}}
      logo = logo_key(1)
      :ok = FileStore.put(logo, "bytes")
      assert FileStore.tags(logo) == {:ok, %{}}
    end

    test "delete_all/2 takes every file an owner has, and leaves an id that starts the same" do
      id = org()
      logo = logo_key(id)
      kept = logo_key(id * 10)
      :ok = FileStore.put(logo, "bytes")
      :ok = FileStore.put(kept, "bytes")

      assert FileStore.delete_all(:orgs, id) == :ok

      assert FileStore.get(logo) == {:error, :not_found}
      assert FileStore.get(kept) == {:ok, "bytes"}
      assert FileStore.delete_all(:orgs, id) == :ok
    end

    test "refuses a key that could leave the store's folder" do
      for key <- ["../outside.jpg", "orgs/../../outside.jpg", "/etc/passwd", "orgs//a", "", "a b"] do
        assert FileStore.put(key, "bytes") == {:error, :invalid_key}, key
        assert FileStore.get(key) == {:error, :invalid_key}, key
        assert FileStore.delete(key) == {:error, :invalid_key}, key
      end
    end
  end

  test "with no store, it is not available and every call says so" do
    key = logo_key(org())
    FileStoreOff.turn_off()

    refute FileStore.available?()
    assert FileStore.put(key, "bytes") == {:error, :off}
    assert FileStore.get(key) == {:error, :off}
    assert FileStore.delete(key) == {:error, :off}
    assert FileStore.delete_all(:orgs, 1) == {:error, :off}
  end

  describe "in S3" do
    setup do
      FileStoreOff.use_s3()
      {:ok, bucket} = Agent.start_link(fn -> %{} end)
      Req.Test.stub(FileStore, &fake_s3(&1, bucket))
      %{bucket: bucket}
    end

    test "puts, gets, tags, and deletes, signed for the bucket in Calgary", %{bucket: bucket} do
      key = FileStore.key(:site, nil, :integration_test, FileStore.new_token(), "a.txt")
      assert FileStore.store() == :s3

      assert FileStore.put(key, "bytes", "text/plain") == :ok
      assert %{tags: "expires=2d", type: "text/plain", auth: auth} = Agent.get(bucket, & &1[key])
      # cspell:ignore HMAC -- AWS's signature algorithm, as the header names it
      assert auth =~ "AWS4-HMAC-SHA256 Credential=test-key-id/"
      assert auth =~ "/ca-west-1/s3/aws4_request"

      assert FileStore.get(key) == {:ok, "bytes"}
      assert FileStore.tags(key) == {:ok, %{"expires" => "2d"}}

      assert FileStore.delete(key) == :ok
      assert FileStore.get(key) == {:error, :not_found}
      assert FileStore.tags(key) == {:error, :not_found}
    end

    test "a logo is put with no expiry tag", %{bucket: bucket} do
      logo = logo_key(4)
      :ok = FileStore.put(logo, "png", "image/png")
      assert %{tags: nil} = Agent.get(bucket, & &1[logo])
    end

    test "delete_all/2 lists the owner's files a page at a time and deletes each", %{
      bucket: bucket
    } do
      for id <- [4, 40], do: :ok = id |> logo_key() |> FileStore.put("png")
      for n <- 1..3, do: Agent.update(bucket, &Map.put(&1, "orgs/4/logo/old-#{n}.png", %{}))

      assert FileStore.delete_all(:orgs, 4) == :ok
      assert bucket |> Agent.get(& &1) |> Map.keys() == ["orgs/40/logo/logo.png"]
    end

    test "says what S3 refused" do
      Req.Test.stub(FileStore, fn conn ->
        Plug.Conn.send_resp(conn, 403, "<Error><Code>AccessDenied</Code></Error>")
      end)

      assert 4 |> logo_key() |> FileStore.put("png") == {:error, "S3 answered 403 AccessDenied"}
    end
  end

  # A bucket in an Agent: enough of S3 for put, get, tagging, delete, and a list two
  # keys a page.
  defp fake_s3(conn, bucket) do
    conn = Plug.Conn.fetch_query_params(conn)
    key = String.trim_leading(conn.request_path, "/")
    s3_call(conn.method, key, conn.query_params, conn, bucket)
  end

  defp s3_call("PUT", key, _params, conn, bucket) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    file = %{
      body: body,
      tags: header(conn, "x-amz-tagging"),
      type: header(conn, "content-type"),
      auth: header(conn, "authorization")
    }

    Agent.update(bucket, &Map.put(&1, key, file))
    Plug.Conn.send_resp(conn, 200, "")
  end

  defp s3_call("GET", "", %{"prefix" => prefix} = params, conn, bucket) do
    skip = String.to_integer(params["continuation-token"] || "0")
    keys = bucket |> Agent.get(&Map.keys/1) |> Enum.filter(&String.starts_with?(&1, prefix))
    {page, rest} = keys |> Enum.sort() |> Enum.drop(skip) |> Enum.split(2)
    next = if rest != [], do: "<NextContinuationToken>2</NextContinuationToken>", else: ""
    xml = Enum.map_join(page, &"<Contents><Key>#{&1}</Key></Contents>") <> next
    Plug.Conn.send_resp(conn, 200, "<ListBucketResult>#{xml}</ListBucketResult>")
  end

  defp s3_call("GET", key, params, conn, bucket) do
    case {Agent.get(bucket, & &1[key]), params} do
      {nil, _params} -> Plug.Conn.send_resp(conn, 404, "<Error><Code>NoSuchKey</Code></Error>")
      {file, %{"tagging" => _}} -> Plug.Conn.send_resp(conn, 200, tagging_xml(file.tags))
      {file, _params} -> Plug.Conn.send_resp(conn, 200, file.body)
    end
  end

  defp s3_call("DELETE", key, _params, conn, bucket) do
    Agent.update(bucket, &Map.delete(&1, key))
    Plug.Conn.send_resp(conn, 204, "")
  end

  defp header(conn, name), do: conn |> Plug.Conn.get_req_header(name) |> List.first()

  defp tagging_xml(nil), do: "<Tagging><TagSet></TagSet></Tagging>"

  defp tagging_xml(tags) do
    [key, value] = String.split(tags, "=")
    "<Tagging><TagSet><Tag><Key>#{key}</Key><Value>#{value}</Value></Tag></TagSet></Tagging>"
  end
end
