defmodule App.Adapter.GoogleWallet.Callback do
  @moduledoc """
  Google Wallet's save and delete callbacks (#389). Google posts a message signed with
  its `ECv2SigningOnly` protocol, the one Tink's `PaymentMethodTokenRecipient` checks:

  1. One of Google's root keys signs an intermediate key, with an expiry.
  2. The intermediate key signs the message, for this issuer.
  3. The message names the class, the object, `"save"` or `"del"`, and its own expiry.

  Pure: the posted JSON, Google's root keys, the issuer ID, and `now` in.
  """

  @protocol "ECv2SigningOnly"
  @sender "GooglePayPasses"

  @doc """
  `{:ok, %{event: :save | :delete, object_id:, class_id:}}`, or `{:error, reason}` when
  any signature, expiry, or field is wrong. `root_keys` are Google's, as
  `fetch_keys/0`'s body lists them.
  """
  def verify(body, root_keys, issuer_id, now) do
    now_ms = DateTime.to_unix(now, :millisecond)

    with %{
           "protocolVersion" => @protocol,
           "signature" => signature,
           "signedMessage" => signed_message,
           "intermediateSigningKey" => %{
             "signedKey" => signed_key,
             "signatures" => key_signatures
           }
         } <- body,
         :ok <- verify_intermediate(signed_key, key_signatures, root_keys),
         {:ok, key} <- intermediate_key(signed_key, now_ms),
         :ok <- check(signed_message, signature, key, issuer_id),
         {:ok, message} <- Jason.decode(signed_message) do
      read(message, now_ms)
    else
      {:error, _reason} = error -> error
      _other -> {:error, :malformed}
    end
  end

  @doc "Google's root keys for the protocol from the keys JSON, as public keys."
  def root_keys(%{"keys" => keys}, now) do
    now_ms = DateTime.to_unix(now, :millisecond)

    for %{"protocolVersion" => @protocol, "keyValue" => value} = key <- keys,
        not expired?(key["keyExpiration"], now_ms),
        {:ok, public_key} <- [public_key(value)],
        do: public_key
  end

  def root_keys(_body, _now), do: []

  # Any root key may have signed the intermediate key.
  defp verify_intermediate(signed_key, signatures, root_keys) do
    signed = length_value([@sender, @protocol, signed_key])

    signed? =
      for signature <- signatures,
          {:ok, der} <- [Base.decode64(signature)],
          key <- root_keys,
          reduce: false,
          do: (acc -> acc or :public_key.verify(signed, :sha256, der, key))

    if signed?, do: :ok, else: {:error, :bad_intermediate_signature}
  end

  defp intermediate_key(signed_key, now_ms) do
    with {:ok, %{"keyValue" => value, "keyExpiration" => expiration}} <- Jason.decode(signed_key),
         false <- expired?(expiration, now_ms),
         {:ok, key} <- public_key(value) do
      {:ok, key}
    else
      true -> {:error, :intermediate_key_expired}
      _other -> {:error, :malformed}
    end
  end

  defp check(signed_message, signature, key, issuer_id) do
    signed = length_value([@sender, to_string(issuer_id), @protocol, signed_message])

    with {:ok, der} <- Base.decode64(signature),
         true <- :public_key.verify(signed, :sha256, der, key) do
      :ok
    else
      _other -> {:error, :bad_signature}
    end
  end

  defp read(
         %{"eventType" => type, "objectId" => object_id, "classId" => class_id} = message,
         now_ms
       )
       when type in ["save", "del"] do
    if expired?(message["expTimeMillis"], now_ms),
      do: {:error, :message_expired},
      else: {:ok, %{event: event(type), object_id: object_id, class_id: class_id}}
  end

  defp read(_message, _now_ms), do: {:error, :malformed}

  defp event("save"), do: :save
  defp event("del"), do: :delete

  # Expiries are milliseconds, as a number or a string. None means no expiry.
  defp expired?(nil, _now_ms), do: false
  defp expired?(ms, now_ms) when is_integer(ms), do: ms <= now_ms

  defp expired?(ms, now_ms) when is_binary(ms) do
    case Integer.parse(ms) do
      {ms, ""} -> ms <= now_ms
      _other -> true
    end
  end

  # A base64 DER SubjectPublicKeyInfo for a P-256 key.
  defp public_key(value) do
    with {:ok, der} <- Base.decode64(value),
         {{:ECPoint, _point}, _params} = key <-
           :public_key.pem_entry_decode({:SubjectPublicKeyInfo, der, :not_encrypted}) do
      {:ok, key}
    else
      _other -> {:error, :malformed}
    end
  rescue
    _error -> {:error, :malformed}
  end

  # Each part as a 4-byte little-endian length, then the part.
  defp length_value(parts),
    do: for(part <- parts, into: <<>>, do: <<byte_size(part)::little-32, part::binary>>)
end
