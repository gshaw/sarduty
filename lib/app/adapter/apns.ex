defmodule App.Adapter.APNs do
  @moduledoc """
  Apple Push Notification service, for Wallet pass updates only. A pass push has an
  empty payload and is signed in by the pass type certificate itself, not an APNs key.
  Pass pushes work only against production APNs.
  """

  require Logger

  @host "https://api.push.apple.com"

  @doc """
  `:ok`, `{:error, :unregistered}` when the phone dropped the pass or its token is bad,
  or `{:error, status}`.
  """
  def push_pass_update(push_token, %{pass_type_id: topic} = credentials) do
    response =
      [
        base_url: @host,
        url: "/3/device/#{push_token}",
        method: :post,
        headers: [{"apns-topic", topic}, {"apns-push-type", "background"}],
        body: "{}",
        retry: false,
        connect_options: [
          protocols: [:http1, :http2],
          transport_opts: client_certificate(credentials)
        ]
      ]
      |> Keyword.merge(Application.get_env(:sarduty, App.Adapter.APNs, []))
      |> Req.request!()

    case {response.status, reason(response.body)} do
      {200, _} -> :ok
      {410, _} -> {:error, :unregistered}
      {400, "BadDeviceToken"} -> {:error, :unregistered}
      {status, _} -> log_error(status, response.body)
    end
  end

  defp reason(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"reason" => reason}} -> reason
      _ -> nil
    end
  end

  defp reason(%{"reason" => reason}), do: reason
  defp reason(_body), do: nil

  defp log_error(status, body) do
    Logger.warning("APNs pass push failed: #{status} #{inspect(body)}")
    {:error, status}
  end

  defp client_certificate(%{certificate: certificate, private_key: private_key}) do
    [{:Certificate, cert_der, _}] = :public_key.pem_decode(certificate)
    [{key_type, key_der, _}] = :public_key.pem_decode(private_key)
    [cert: cert_der, key: {key_type, key_der}]
  end
end
