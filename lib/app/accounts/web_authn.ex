defmodule App.Accounts.WebAuthn do
  @moduledoc """
  The WebAuthn side of passkeys (#129), through the wax_ library: the options a browser
  needs to make or use a passkey, and the checks on what it sends back. The relying party
  is the app's own host, such as sarduty.com, so a passkey made here works only here.

  Every passkey is discoverable and needs the person to unlock their device (user
  verification), so the login page can offer passkeys before anyone types an email.
  Binary values travel as unpadded base64url, as the browser's JSON forms write them.
  """

  alias App.Accounts.User
  alias App.Accounts.UserPasskey

  # How long a challenge stands, in seconds. A login page left open still works when
  # someone later picks their passkey from the email box.
  @timeout 30 * 60

  def registration_challenge, do: Wax.new_registration_challenge(opts())

  def authentication_challenge, do: Wax.new_authentication_challenge(opts())

  @doc "An authentication challenge rebuilt from its bytes and when it was issued."
  def authentication_challenge(bytes, issued_at) do
    challenge = Wax.new_authentication_challenge([bytes: bytes] ++ opts())
    %{challenge | issued_at: issued_at}
  end

  # SAR Duty keeps no attestation, so it trusts no attestation root either.
  defp opts do
    [
      origin: Web.Endpoint.url(),
      rp_id: Web.Endpoint.host(),
      user_verification: "required",
      attestation: "none",
      verify_trust_root: false,
      timeout: @timeout
    ]
  end

  @doc """
  The options for navigator.credentials.create(), as JSON. `passkeys` are the user's
  own, so the same password manager can't save a second one.
  """
  def creation_options(challenge, %User{} = user, passkeys) do
    %{
      challenge: encode(challenge.bytes),
      rp: %{id: challenge.rp_id, name: "SAR Duty"},
      user: %{id: encode(user_handle(user)), name: user.email, displayName: user.email},
      pubKeyCredParams: [%{type: "public-key", alg: -7}, %{type: "public-key", alg: -257}],
      timeout: @timeout * 1000,
      attestation: "none",
      authenticatorSelection: %{
        residentKey: "required",
        requireResidentKey: true,
        userVerification: "required"
      },
      excludeCredentials: Enum.map(passkeys, &%{type: "public-key", id: encode(&1.credential_id)})
    }
  end

  @doc "The options for navigator.credentials.get(), as JSON: any passkey for this site."
  def request_options(challenge) do
    %{
      challenge: encode(challenge.bytes),
      rpId: challenge.rp_id,
      timeout: @timeout * 1000,
      userVerification: "required",
      allowCredentials: []
    }
  end

  @doc """
  Checks a new passkey from navigator.credentials.create(). `params` holds
  `"attestation_object"` and `"client_data_json"`. `{:ok, attrs}` for
  App.Accounts.UserPasskey.insert/2, or `:error`.
  """
  def register(challenge, %{"attestation_object" => object, "client_data_json" => client_data}) do
    with {:ok, object} <- decode(object),
         {:ok, client_data} <- decode(client_data),
         {:ok, {auth_data, _attestation}} <- Wax.register(object, client_data, challenge) do
      credential = auth_data.attested_credential_data
      aaguid = uuid(credential.aaguid)

      {:ok,
       %{
         credential_id: credential.credential_id,
         public_key: :erlang.term_to_binary(credential.credential_public_key),
         sign_count: auth_data.sign_count,
         aaguid: aaguid,
         name: UserPasskey.name_for(aaguid)
       }}
    else
      _ -> :error
    end
  end

  def register(_challenge, _params), do: :error

  @doc """
  Checks a login from navigator.credentials.get() against `passkey`. `params` holds
  `"authenticator_data"`, `"client_data_json"`, `"signature"`, and `"user_handle"`.
  `{:ok, sign_count}`, or `:error`.
  """
  def authenticate(challenge, params, %UserPasskey{} = passkey) do
    with {:ok, answer} <- decode_answer(params),
         :ok <- same_user(params["user_handle"], passkey),
         {:ok, %{sign_count: count}} <- check(challenge, answer, passkey),
         :ok <- not_cloned(passkey.sign_count, count) do
      {:ok, count}
    else
      _ -> :error
    end
  end

  defp decode_answer(params) do
    with {:ok, auth_data} <- decode(params["authenticator_data"]),
         {:ok, client_data} <- decode(params["client_data_json"]),
         {:ok, signature} <- decode(params["signature"]) do
      {:ok, {auth_data, client_data, signature}}
    end
  end

  defp check(challenge, {auth_data, client_data, signature}, passkey) do
    id = passkey.credential_id
    credentials = [{id, UserPasskey.cose_key(passkey)}]
    Wax.authenticate(id, auth_data, signature, client_data, challenge, credentials)
  end

  # The user handle, when the browser sends one, must be the one this passkey was made
  # for.
  defp same_user(handle, _passkey) when handle in [nil, ""], do: :ok

  defp same_user(handle, passkey) do
    if decode(handle) == {:ok, user_handle(%User{id: passkey.user_id})}, do: :ok, else: :error
  end

  # Synced passkeys always count 0. A counter that didn't go up means a copied key.
  defp not_cloned(0, _new), do: :ok
  defp not_cloned(old, new) when new > old, do: :ok
  defp not_cloned(_old, _new), do: :error

  # The WebAuthn user id: the user's id, as 8 bytes. It holds no email or name.
  defp user_handle(%User{id: id}), do: <<id::unsigned-big-64>>

  def encode(binary), do: Base.url_encode64(binary, padding: false)

  def decode(text) when is_binary(text), do: Base.url_decode64(text, padding: false)
  def decode(_text), do: :error

  defp uuid(<<a::binary-4, b::binary-2, c::binary-2, d::binary-2, e::binary-6>>) do
    Enum.map_join([a, b, c, d, e], "-", &Base.encode16(&1, case: :lower))
  end

  defp uuid(_aaguid), do: nil
end
