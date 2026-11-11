defmodule App.PasskeyFixtures do
  @moduledoc """
  A software authenticator for passkey tests (#129). It makes a P-256 key and answers
  WebAuthn challenges the way a browser and a password manager would, so tests run the
  real wax_ checks. Its answers are the params the passkey hooks send.
  """

  alias App.Accounts.User
  alias App.Accounts.UserPasskey
  alias App.Accounts.WebAuthn

  # iCloud Keychain's AAGUID, so a new passkey gets its name.
  @aaguid Base.decode16!("FBFC3007154E4ECC8C0B6E020557D7BD")

  # cspell:ignore ecdh -- :crypto's name for an elliptic-curve key pair
  def authenticator(attrs \\ %{}) do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)

    Map.merge(
      %{
        credential_id: :crypto.strong_rand_bytes(16),
        public: public,
        private: private,
        aaguid: @aaguid,
        sign_count: 0
      },
      attrs
    )
  end

  @doc "A passkey saved for `user`, and the authenticator that holds its private key."
  def passkey_fixture(%User{} = user, authenticator \\ authenticator()) do
    challenge = WebAuthn.registration_challenge()
    {:ok, attrs} = WebAuthn.register(challenge, create_answer(authenticator, challenge))
    {:ok, passkey} = UserPasskey.insert(user, Map.put(attrs, :added_with, "iPhone, Safari"))
    {passkey, authenticator}
  end

  @doc "What navigator.credentials.create() answers to a registration challenge."
  def create_answer(authenticator, challenge, opts \\ []) do
    client_data = client_data("webauthn.create", challenge, opts)
    <<4, x::binary-32, y::binary-32>> = authenticator.public
    cose_key = CBOR.encode(%{1 => 2, 3 => -7, -1 => 1, -2 => bytes(x), -3 => bytes(y)})
    id = authenticator.credential_id

    auth_data =
      rp_id_hash(challenge, opts) <>
        <<0x45, authenticator.sign_count::32>> <>
        authenticator.aaguid <> <<byte_size(id)::16>> <> id <> cose_key

    attestation =
      CBOR.encode(%{"fmt" => "none", "attStmt" => %{}, "authData" => bytes(auth_data)})

    %{
      "attestation_object" => WebAuthn.encode(attestation),
      "client_data_json" => WebAuthn.encode(client_data)
    }
  end

  @doc """
  What navigator.credentials.get() answers to a login challenge, as the login page's
  hidden form posts it. `user` sets the user handle; `attachment` is "platform" for a
  passkey on the device itself.
  """
  def get_answer(authenticator, challenge, %User{} = user, opts \\ []) do
    client_data = client_data("webauthn.get", challenge, opts)
    auth_data = rp_id_hash(challenge, opts) <> <<0x05, authenticator.sign_count::32>>
    signed = auth_data <> :crypto.hash(:sha256, client_data)
    signature = :crypto.sign(:ecdsa, :sha256, signed, [authenticator.private, :prime256v1])

    %{
      "credential_id" => WebAuthn.encode(authenticator.credential_id),
      "authenticator_data" => WebAuthn.encode(auth_data),
      "client_data_json" => WebAuthn.encode(client_data),
      "signature" => WebAuthn.encode(signature),
      "user_handle" => WebAuthn.encode(<<user.id::unsigned-big-64>>),
      "attachment" => Keyword.get(opts, :attachment, "platform")
    }
  end

  defp client_data(type, challenge, opts) do
    Jason.encode!(%{
      type: type,
      challenge: WebAuthn.encode(challenge.bytes),
      origin: Keyword.get(opts, :origin, challenge.origin),
      crossOrigin: false
    })
  end

  defp rp_id_hash(challenge, opts),
    do: :crypto.hash(:sha256, Keyword.get(opts, :rp_id, challenge.rp_id))

  defp bytes(value), do: %CBOR.Tag{tag: :bytes, value: value}
end
