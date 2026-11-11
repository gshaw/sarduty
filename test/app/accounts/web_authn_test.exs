defmodule App.Accounts.WebAuthnTest do
  use ExUnit.Case, async: true

  import App.PasskeyFixtures

  alias App.Accounts.User
  alias App.Accounts.UserPasskey
  alias App.Accounts.WebAuthn

  @user %User{id: 42, email: "alex.chen@example.com"}

  # A passkey as App.Accounts.UserPasskey.insert/2 would save it.
  defp registered(authenticator) do
    challenge = WebAuthn.registration_challenge()
    {:ok, attrs} = WebAuthn.register(challenge, create_answer(authenticator, challenge))
    struct(UserPasskey, Map.put(attrs, :user_id, @user.id))
  end

  describe "register/2" do
    test "keeps the key, and names the passkey from its AAGUID" do
      key = authenticator()
      challenge = WebAuthn.registration_challenge()

      assert {:ok, attrs} = WebAuthn.register(challenge, create_answer(key, challenge))
      assert attrs.credential_id == key.credential_id
      assert attrs.aaguid == "fbfc3007-154e-4ecc-8c0b-6e020557d7bd"
      assert attrs.name == "iCloud Keychain"
      assert attrs.sign_count == 0
    end

    test "names an unknown authenticator Passkey" do
      key = authenticator(%{aaguid: <<0::128>>})
      challenge = WebAuthn.registration_challenge()

      assert {:ok, %{name: "Passkey", aaguid: "00000000-0000-0000-0000-000000000000"}} =
               WebAuthn.register(challenge, create_answer(key, challenge))
    end

    test "refuses another site's origin, another challenge, or a missing field" do
      key = authenticator()
      challenge = WebAuthn.registration_challenge()

      assert WebAuthn.register(
               challenge,
               create_answer(key, challenge, origin: "https://evil.example")
             ) ==
               :error

      other = WebAuthn.registration_challenge()
      assert WebAuthn.register(challenge, create_answer(key, other)) == :error
      assert WebAuthn.register(challenge, %{"client_data_json" => "e30"}) == :error
    end
  end

  describe "authenticate/3" do
    test "accepts the passkey's signature and returns its sign count" do
      key = authenticator()
      passkey = registered(key)
      challenge = WebAuthn.authentication_challenge()

      assert WebAuthn.authenticate(challenge, get_answer(key, challenge, @user), passkey) ==
               {:ok, 0}
    end

    test "refuses another key, another site, or an expired challenge" do
      key = authenticator()
      passkey = registered(key)
      challenge = WebAuthn.authentication_challenge()

      other_key = %{authenticator() | credential_id: key.credential_id}

      assert WebAuthn.authenticate(challenge, get_answer(other_key, challenge, @user), passkey) ==
               :error

      params = get_answer(key, challenge, @user, rp_id: "evil.example")
      assert WebAuthn.authenticate(challenge, params, passkey) == :error

      old = WebAuthn.authentication_challenge(challenge.bytes, challenge.issued_at - 31 * 60)
      assert WebAuthn.authenticate(old, get_answer(key, old, @user), passkey) == :error
    end

    test "refuses a user handle that isn't the passkey's user" do
      key = authenticator()
      passkey = registered(key)
      challenge = WebAuthn.authentication_challenge()
      params = get_answer(key, challenge, %User{id: 7})

      assert WebAuthn.authenticate(challenge, params, passkey) == :error
      assert {:ok, 0} = WebAuthn.authenticate(challenge, %{params | "user_handle" => ""}, passkey)
    end

    test "refuses a sign count that didn't go up, as from a copied key" do
      key = authenticator(%{sign_count: 5})
      passkey = %{registered(key) | sign_count: 5}
      challenge = WebAuthn.authentication_challenge()

      assert WebAuthn.authenticate(challenge, get_answer(key, challenge, @user), passkey) ==
               :error

      key = %{key | sign_count: 6}

      assert WebAuthn.authenticate(challenge, get_answer(key, challenge, @user), passkey) ==
               {:ok, 6}
    end

    test "rebuilds a challenge from its bytes, as the session keeps it" do
      key = authenticator()
      passkey = registered(key)
      first = WebAuthn.authentication_challenge()
      challenge = WebAuthn.authentication_challenge(first.bytes, first.issued_at)

      assert {:ok, 0} = WebAuthn.authenticate(challenge, get_answer(key, first, @user), passkey)
    end
  end

  test "creation options exclude the user's own passkeys and hold no email in the id" do
    passkey = registered(authenticator())
    challenge = WebAuthn.registration_challenge()
    options = WebAuthn.creation_options(challenge, @user, [passkey])

    assert options.user.id == WebAuthn.encode(<<42::unsigned-big-64>>)
    assert options.user.name == "alex.chen@example.com"
    assert options.authenticatorSelection.residentKey == "required"

    assert options.excludeCredentials == [
             %{type: "public-key", id: WebAuthn.encode(passkey.credential_id)}
           ]

    assert options.challenge == WebAuthn.encode(challenge.bytes)
  end
end
