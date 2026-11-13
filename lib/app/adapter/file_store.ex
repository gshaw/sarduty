defmodule App.Adapter.FileStore do
  @moduledoc """
  Where SAR Duty keeps files (#1067): never in SQLite, which Litestream copies whole.
  This module is the only place that knows where they are, and the only one that makes
  a key. Callers make one with `key/5`, then put, get, and delete by it. docs/files.md
  has the layout, every kind, and the bucket's settings.

  `config :sarduty, App.Adapter.FileStore` picks the store:

  - `bucket:`, `region:`, `access_key_id:`, `secret_access_key:`: S3, signed with
    Req's `aws_sigv4`. Production's `sarduty-files`, and dev's `sarduty-files-dev` when
    FILES_BUCKET is set (config/runtime.exs).
  - `dir:`, a folder on disk, for dev without a key and for tests. A key is the file's
    path under it.
  - Neither: no store. `store/0` is nil and every call answers `{:error, :off}`.
  """

  # cspell:ignore enoent -- the file system's "no such file", as File's functions name it

  # Every kind of file: its folder name, whose it is, whether each file has its own
  # random token, and the `expires` tag S3 deletes it by, if any. A new kind is a line
  # here and a row in docs/files.md; App.Adapter.FileStoreKeysTest checks both.
  @kinds %{
    logo: %{folder: "logo", owner: :orgs, token: false, expires: nil},
    integration_test: %{folder: "integration-test", owner: :site, token: true, expires: "2d"}
  }

  @owners %{teams: "teams", orgs: "orgs", site: "site"}

  @doc "Every kind, `{kind, %{folder:, owner:, token:, expires:}}`, for docs/files.md's test."
  def kinds, do: @kinds

  @doc """
  The one way to make a key: `{owner}/{id}/{kind}/{token}/{file}`. `owner` is `:teams`,
  `:orgs`, or `:site`, which has no id. `token` is the row's random token, or nil for a
  kind that has none, like an organization's logo. `file` is `{variant}.{ext}`.

      key(:orgs, 4, :logo, nil, "logo.png")              # "orgs/4/logo/logo.png"
      key(:site, nil, :integration_test, "k3f9", "a.txt") # "site/integration-test/k3f9/a.txt"
  """
  def key(owner, id, kind, token, file) when is_binary(file) do
    %{folder: folder, owner: kind_owner, token: tokened} = Map.fetch!(@kinds, kind)
    if owner != kind_owner, do: raise(ArgumentError, "#{kind} belongs to #{kind_owner}")
    check_token!(kind, tokened, token)
    [prefix(owner, id), folder, token, file] |> Enum.reject(&is_nil/1) |> Enum.join("/")
  end

  @doc "A new random token for a row's files: 16 characters, safe in a key."
  def new_token, do: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp check_token!(_kind, false, nil), do: :ok
  defp check_token!(kind, false, _token), do: raise(ArgumentError, "#{kind} takes no token")

  defp check_token!(kind, true, token) do
    unless is_binary(token) and token =~ ~r/\A[A-Za-z0-9_-]{8,}\z/,
      do: raise(ArgumentError, "#{kind} needs a token")
  end

  defp prefix(:site, nil), do: @owners.site

  defp prefix(owner, id) when owner in [:teams, :orgs] and is_integer(id),
    do: "#{@owners[owner]}/#{id}"

  @doc "Which store this server has: `:s3`, `:disk`, or nil."
  def store do
    config = config()

    cond do
      config[:bucket] not in [nil, ""] -> :s3
      config[:dir] not in [nil, ""] -> :disk
      true -> nil
    end
  end

  @doc "The S3 bucket's name, or nil for a store on disk or none."
  def bucket, do: config()[:bucket]

  @doc "Whether there is a store at all."
  def available?, do: store() != nil

  @doc """
  Keeps `bytes` at `key`, in place of what was there, tagged with its kind's `expires`.
  `:ok` or `{:error, reason}`.
  """
  def put(key, bytes, content_type \\ "application/octet-stream")
      when is_binary(key) and is_binary(bytes) do
    with {:ok, key} <- check(key) do
      put_in_store(store(), key, bytes, content_type)
    end
  end

  @doc "The file at `key`: `{:ok, bytes}`, `{:error, :not_found}`, or `{:error, reason}`."
  def get(key) when is_binary(key) do
    with {:ok, key} <- check(key), do: get_from_store(store(), key)
  end

  @doc """
  The file's tags, as S3 keeps them: `{:ok, %{"expires" => "2d"}}`. The disk store keeps
  none, so it answers with what its kind would be tagged.
  """
  def tags(key) when is_binary(key) do
    with {:ok, key} <- check(key), do: tags_in_store(store(), key)
  end

  @doc "Deletes the file at `key`. One that is not there is `:ok` too."
  def delete(key) when is_binary(key) do
    with {:ok, key} <- check(key), do: delete_from_store(store(), key)
  end

  @doc """
  Deletes every file a team or an organization owns: `delete_all(:orgs, 4)` takes
  `orgs/4/…` and leaves `orgs/40/…`. `:ok` when there were none.
  """
  def delete_all(owner, id) when owner in [:teams, :orgs] do
    if store(), do: delete_all_in_store(store(), prefix(owner, id) <> "/"), else: {:error, :off}
  end

  # A key is made by key/5, so a bad one is a bug, but a key never leaves the store's
  # folder or names another bucket: segments of letters, digits, `.`, `_`, and `-`, and
  # none that is only dots.
  defp check(key) do
    segments = String.split(key, "/")

    cond do
      store() == nil -> {:error, :off}
      Enum.all?(segments, &valid_segment?/1) -> {:ok, key}
      true -> {:error, :invalid_key}
    end
  end

  defp valid_segment?(segment),
    do: segment =~ ~r/\A[A-Za-z0-9._-]+\z/ and not (segment =~ ~r/\A\.+\z/)

  defp expires(key) do
    folder = key |> String.split("/") |> folder_of()
    Enum.find_value(@kinds, fn {_kind, kind} -> kind.folder == folder && kind.expires end)
  end

  # `site/{kind}/…` has no id; `teams/{id}/{kind}/…` and `orgs/{id}/{kind}/…` do.
  defp folder_of(["site", folder | _rest]), do: folder
  defp folder_of([_owner, _id, folder | _rest]), do: folder
  defp folder_of(_segments), do: nil

  ## Disk

  defp put_in_store(:disk, key, bytes, _content_type) do
    # Written beside it and moved into place, so a read never gets half a file.
    path = path(key)
    partial = "#{path}.#{System.unique_integer([:positive])}.part"

    with :ok <- path |> Path.dirname() |> File.mkdir_p(),
         :ok <- File.write(partial, bytes) do
      File.rename(partial, path)
    end
  end

  defp put_in_store(:s3, key, bytes, content_type) do
    headers =
      [{"content-type", content_type}] ++
        if expires = expires(key), do: [{"x-amz-tagging", "expires=#{expires}"}], else: []

    case s3(:put, key, body: bytes, headers: headers) do
      {:ok, %{status: 200}} -> :ok
      other -> s3_error(other)
    end
  end

  defp get_from_store(:disk, key) do
    case key |> path() |> File.read() do
      {:ok, bytes} -> {:ok, bytes}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_from_store(:s3, key) do
    case s3(:get, key) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      other -> s3_error(other)
    end
  end

  defp tags_in_store(:disk, key) do
    if key |> path() |> File.exists?(),
      do: {:ok, if(expires = expires(key), do: %{"expires" => expires}, else: %{})},
      else: {:error, :not_found}
  end

  defp tags_in_store(:s3, key) do
    case s3(:get, key, params: [tagging: ""]) do
      {:ok, %{status: 200, body: body}} -> {:ok, parse_tags(body)}
      {:ok, %{status: 404}} -> {:error, :not_found}
      other -> s3_error(other)
    end
  end

  defp delete_from_store(:disk, key) do
    case key |> path() |> File.rm() do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_from_store(:s3, key) do
    case s3(:delete, key) do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      other -> s3_error(other)
    end
  end

  defp delete_all_in_store(:disk, prefix) do
    case prefix |> path() |> File.rm_rf() do
      {:ok, _removed} -> :ok
      {:error, reason, _file} -> {:error, reason}
    end
  end

  # One delete at a time, stopping at the first that fails.
  defp delete_all_in_store(:s3, prefix) do
    with {:ok, keys} <- list(prefix, nil, []) do
      Enum.reduce_while(keys, :ok, fn key, :ok -> key |> delete_s3() |> continue?() end)
    end
  end

  defp delete_s3(key), do: delete_from_store(:s3, key)

  defp continue?(:ok), do: {:cont, :ok}
  defp continue?(error), do: {:halt, error}

  # Every key under `prefix`, a page of up to 1000 at a time.
  defp list(prefix, continuation, keys) do
    params =
      [{:"list-type", 2}, {:prefix, prefix}] ++
        if continuation, do: [{:"continuation-token", continuation}], else: []

    case s3(:get, "", params: params) do
      {:ok, %{status: 200, body: body}} ->
        keys = keys ++ xml_values(body, "Key")

        case xml_values(body, "NextContinuationToken") do
          [next] -> list(prefix, next, keys)
          [] -> {:ok, keys}
        end

      other ->
        s3_error(other)
    end
  end

  defp path(key), do: Path.join(config()[:dir], key)

  ## S3

  defp s3(method, key, options \\ []) do
    config = config()
    region = config[:region] || "ca-west-1"

    [
      method: method,
      url: "https://#{config[:bucket]}.s3.#{region}.amazonaws.com/#{key}",
      aws_sigv4: [
        access_key_id: config[:access_key_id],
        secret_access_key: config[:secret_access_key],
        service: :s3,
        region: region
      ],
      decode_body: false
    ]
    |> Keyword.merge(options)
    |> Keyword.merge(Keyword.take(config, [:plug]))
    |> Req.request()
  end

  defp s3_error({:ok, %{status: status, body: body}}) do
    case xml_values(body, "Code") do
      [code | _] -> {:error, "S3 answered #{status} #{code}"}
      [] -> {:error, "S3 answered #{status}"}
    end
  end

  defp s3_error({:error, exception}), do: {:error, Exception.message(exception)}

  @doc false
  def parse_tags(xml) do
    ~r{<Tag>\s*<Key>([^<]*)</Key>\s*<Value>([^<]*)</Value>\s*</Tag>}
    |> Regex.scan(xml, capture: :all_but_first)
    |> Map.new(fn [key, value] -> {key, value} end)
  end

  defp xml_values(xml, element) when is_binary(xml) do
    ~r{<#{element}>([^<]*)</#{element}>}
    |> Regex.scan(xml, capture: :all_but_first)
    |> List.flatten()
  end

  defp xml_values(_body, _element), do: []

  defp config, do: Application.get_env(:sarduty, __MODULE__, [])
end
