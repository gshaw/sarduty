defmodule App.Adapter.R2 do
  @moduledoc """
  The Litestream replica in Cloudflare R2, read through R2's S3 API with Litestream's own
  keys. Only lists: nothing here writes to the bucket.
  """

  @doc "Whether the bucket and keys are set, as they are on Fly."
  def configured? do
    config = config()
    Enum.all?([:account_id, :access_key_id, :secret_access_key], &(config[&1] not in [nil, ""]))
  end

  @doc """
  The newest transaction in the replica: the highest end of a level 0 file's range.
  Litestream 0.5 names those `<path>/0000/<first>-<last>.ltx`, in hex. `{:ok, txid}`,
  `{:ok, nil}` for none, or `{:error, reason}`.
  """
  def fetch_newest_txid do
    config = config()

    request =
      [
        url: "https://#{config[:account_id]}.r2.cloudflarestorage.com/#{config[:bucket]}",
        params: ["list-type": 2, prefix: "#{config[:path]}/0000/"],
        aws_sigv4: [
          access_key_id: config[:access_key_id],
          secret_access_key: config[:secret_access_key],
          service: :s3,
          region: "auto"
        ],
        retry: false,
        decode_body: false
      ] ++ Keyword.take(config, [:plug])

    case Req.get(request) do
      {:ok, %{status: 200, body: body}} -> {:ok, newest_txid(body)}
      {:ok, %{status: status}} -> {:error, "R2 answered #{status}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  @doc "Pure. The highest txid among the `.ltx` keys in an S3 list response, or nil."
  def newest_txid(xml) do
    ~r{<Key>[^<]*/[0-9a-f]+-([0-9a-f]+)\.ltx</Key>}
    |> Regex.scan(xml, capture: :all_but_first)
    |> Enum.map(fn [last] -> String.to_integer(last, 16) end)
    |> Enum.max(fn -> nil end)
  end

  defp config, do: Application.get_env(:sarduty, __MODULE__, [])
end
